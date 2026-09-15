extends Node2D
## 游戏协调者。场景结构见 main.tscn。
##
## 从 pygame 移植时最大的一处结构改动：**不再手写世界→屏幕变换**。
## 原实现用一个 `world_to_screen()` 函数（缩放 + 侧栏偏移）在所有绘制与粒子
## 位置里手动调用，任何一处漏乘 scaling 就会错位（实测踩过 350px 的固定偏移）。
## 现在改用官方 `Camera2D`：世界坐标就是世界坐标，转换由引擎负责。
##
## 职责划分：
##   * `ball.tscn` / `ring.tscn` 自己管好自己的运动、旋转与碰撞（自包含场景）。
##   * 本脚本只做协调：开局、判负、结算、把信号翻译成特效调用。
##   * UI 是独立的 `Control` 场景，通过信号把配置交回来。
##
## 所有可调参数集中在 `scripts/config.gd`（`Config.*`），本文件只管逻辑。

enum State { MENU, PLAY, SETTLE }

var state := State.MENU
var wins := 0
var cfg := Config.DEFAULT_CFG.duplicate()

## 是否处于离线渲染（Movie Maker mode）。由官方 feature tag `movie` 判定 ——
## 用 `--write-movie` 启动时引擎会置上它，`OS.has_feature("movie")` 即为 true
## （已实测）。这是官方给的「只在录制时改行为」的钩子，不要去嗅探命令行参数。
var _movie_mode := false

var _camera: Camera2D
var _rings_root: Node2D
var _ball: Ball

@onready var _fx: Node2D = $ParticleFX
@onready var _celebration: Node2D = $CelebrationFX
@onready var _audio: Node = $AudioFX
@onready var _limiter: Area2D = $PlayfieldLimiter
@onready var _ui: CanvasLayer = $UI


func _ready() -> void:
	_camera = $World/Camera2D
	_rings_root = $World/Rings
	_ui.start_game.connect(_on_start_game)
	_ui.apply_and_restart.connect(_on_apply_and_restart)
	_ui.exit_to_menu.connect(_on_exit_to_menu)
	_ui.ui_click.connect(_on_ui_click)
	_celebration.finished.connect(_on_celebration_finished)
	_limiter.body_exited.connect(_on_ball_left_playfield)
	_fx.stop_trail()
	_celebration.visible = false
	_ui.set_wins(wins)
	_sync_camera()
	_sync_limiter()

	_movie_mode = OS.has_feature("movie")
	if _movie_mode:
		_begin_movie_mode()


## 进入离线渲染：跳过主菜单直接开球，并把这一局钉死成可复现的。
##
## ⚠️ 帧率不是在这里设的 —— 用 `--write-movie`（默认 60）或 `--fixed-fps N`。
## 这里只负责「把已经固定的 delta 变得真的一致」：`physics_jitter_fix`（默认 0.5）
## 会让引擎为了迁就物理时钟去**微调**每帧 delta，实测 30fps 下 delta 在
## 0.0325 ~ 0.033333 之间抖（spread 8.3e-4），60/120fps 恰好整除才看不出来。
## 该开关已由 `project.godot` 的 `.movie` 特性标签覆盖置 0；这里再设一次是
## 兜底 —— 免得有人删了那行却以为录制还是确定的。
func _begin_movie_mode() -> void:
	seed(Config.MOVIE_SEED)
	Engine.physics_jitter_fix = 0.0
	_ui.set_menu_visible(false)
	if Config.MOVIE_HIDE_UI:
		_ui.set_chrome_visible(false)
	start_round(true)


## 「球已飞出可见范围」判定区。用官方 `Area2D` 的 `body_exited` 信号，
## 而不是自己每帧算矩形包含 —— 判定范围也会随视口与侧栏变化，所以在
## `_process` 里同步（`_process` 每帧都跑，视口尺寸变化自然被跟上）。
##
## 尺寸取「视口能容纳的世界范围」再放宽 `Config.PLAYFIELD_MARGIN` 倍：
## 太紧会在球还看得见时就判出界，太松则要等很久。
func _sync_limiter() -> void:
	var vp := Vector2(get_viewport_rect().size)
	var span := vp / _camera.zoom * Config.PLAYFIELD_MARGIN
	var shape := ($PlayfieldLimiter/CollisionShape2D as CollisionShape2D).shape as RectangleShape2D
	# 只在尺寸真的变了才写：每帧无条件写会白白触发一次物理形状更新。
	if shape != null and shape.size != span:
		shape.size = span
	# 判定区就套在盘面中心上。旧版写 `WORLD_CENTER * WORLD_SCALE`，而
	# `CollisionShape2D` 自己还带一个 (500,500) 的局部偏移，两层错开之后
	# 这个矩形其实并不以盘面为中心 —— 只是靠 PLAYFIELD_MARGIN 够大才没出事。
	# 现在 shape 的局部偏移已在 `main.tscn` 里归零，位置就是盘心。
	($PlayfieldLimiter as Area2D).position = Config.WORLD_CENTER


func _process(_delta: float) -> void:
	# 侧栏显隐会改变盘面该占的区域，只需更新相机。
	_sync_camera()
	_sync_limiter()
	_ui.set_wins(wins)
	if state == State.PLAY and _ball != null and is_instance_valid(_ball):
		# 官方拖尾发射器要每帧跟到球的位置，否则拖尾会留在原地发射。
		_fx.emit_trail(_ball.global_position, Config.BALL_WORLD_RADIUS, _ball.color)
	# `queue_free()` 要到帧末才真正把环移出树，所以碎裂当帧 child_count 仍非 0。
	# 通关判定放在这里等它真正清空，而不是在信号回调里抢答。
	if state == State.PLAY and _rings_root.get_child_count() == 0 and _ball != null:
		_begin_settle()


## 取景：把盘面摆到**可见游戏区**正中，并让它占满该区域宽度的 `PLAYFIELD_FILL`。
##
## 缩放**只在这里**发生一次（`Camera2D.zoom`），几何与物理全是世界单位。
## 旧版把缩放乘在几何里、又乘在相机上（净 0.49），盘面只占画面宽 33%；
## 而且内容放在 `WORLD_CENTER × WORLD_SCALE`、相机看 `WORLD_CENTER`，
## 盘面整体偏离中心 `(-105, -105)` px。现在两者共用 `Config.WORLD_CENTER`。
##
## zoom 由「盘面直径 ÷ 可见区宽度」反推，所以换分辨率不会改变构图。
## ⚠️ `_disc_diameter()` 返回的**已经是直径**，别再乘 2 —— 实测写成
##    `/(_disc_diameter() * 2.0)` 会让盘面只占宽度的一半（46% 而不是 92%）。
## `Camera2D.offset` 是**屏幕像素**，除以 zoom 才是世界单位。
func _sync_camera() -> void:
	var vp := Vector2(get_viewport_rect().size)
	var sidebar_on: bool = _ui.sidebar_visible() and state != State.MENU
	# 可见游戏区 = 视口减掉侧栏；侧栏展开时盘面要缩小到剩余区域里，免得被盖住。
	var area_w := vp.x - (Config.SIDEBAR_WIDTH if sidebar_on else 0.0)
	var zoom := area_w * Config.PLAYFIELD_FILL / _disc_diameter()
	_camera.zoom = Vector2(zoom, zoom)
	# 盘心对齐到可见区中心：世界中心本来映射到视口中心，
	# 多了侧栏就要往左挪半个侧栏宽（屏幕像素）→ 除以 zoom 换成世界单位。
	var shift_px := -Config.SIDEBAR_WIDTH * 0.5 if sidebar_on else 0.0
	_camera.offset = Vector2(-shift_px / zoom, 0.0)


## 最外圈环的外沿直径（世界单位）。取景按它算，所以盘面永远刚好占满设定的比例。
## 环还没实例化（主菜单）时按当前配置推算。
func _disc_diameter() -> float:
	var count: int = maxi(1, int(cfg["rings_count"]))
	var outermost := Config.RING_FIRST_WORLD_RADIUS \
			+ float(count - 1) * Config.RING_RADIUS_STEP
	return Ring.outer_world_radius(outermost, Config.RING_WORLD_THICKNESS) * 2.0


# --------------------------------------------------------------------- 开局

func start_round(apply_cfg: bool = false) -> void:
	if apply_cfg:
		cfg = _ui.cfg.duplicate()
	_clear_round()
	_spawn_ball()
	_spawn_rings()
	if _fx != null:
		_fx.restart_trail()
	if _celebration != null:
		_celebration.finish_now()
	state = State.PLAY


func _clear_round() -> void:
	for c in _rings_root.get_children():
		c.queue_free()
	if _ball != null and is_instance_valid(_ball):
		_ball.queue_free()
	_ball = null


func _spawn_ball() -> void:
	_ball = (load(Config.SCENE_BALL) as PackedScene).instantiate() as Ball
	# 原版每帧 10 次子步、每次重力 gravity/10，所以每帧重力增量就是 gravity。
	_ball.gravity_per_tick = float(cfg["gravity"])
	# 原版按「世界单位/帧」比较 1.0，这里保持同一尺度。
	_ball.min_speed = Config.BALL_MIN_SPEED
	_ball.color = _resolve_color(String(cfg["ball_mode"]), String(cfg["ball_val"]))
	_ball.bounced.connect(_on_ball_bounced)
	$World.add_child(_ball)
	var vx: float = [-Config.BALL_LAUNCH_SPEED_X, Config.BALL_LAUNCH_SPEED_X][randi() % 2]
	_ball.launch(Config.WORLD_CENTER, vx, randf_range(-Config.BALL_LAUNCH_SPEED_Y,
			Config.BALL_LAUNCH_SPEED_Y))


func _spawn_rings() -> void:
	var count: int = int(cfg["rings_count"])
	for i in range(count):
		var spin: float = [-1.0, 1.0][randi() % 2] * float(cfg["rotation_speed"])
		var ring := (load(Config.SCENE_RING) as PackedScene).instantiate() as Ring
		ring.world_radius = Config.RING_FIRST_WORLD_RADIUS + i * Config.RING_RADIUS_STEP
		ring.world_thickness = Config.RING_WORLD_THICKNESS
		ring.gap_deg = float(cfg["gap_size"])
		ring.angle_deg = randf_range(0.0, 360.0)
		ring.spin = spin
		ring.color = _resolve_color(String(cfg["ring_mode"]), String(cfg["ring_val"]))
		# 缺口探测区要按球半径外扩，`body_entered` 才对得上球**圆心**的位置。
		ring.ball_radius = Config.BALL_WORLD_RADIUS
		# 碎环由环自己的 EscapeDetector 判定后发信号通知，main 不再逐帧替球做几何判断。
		ring.escaped.connect(_on_ring_escaped)
		_rings_root.add_child(ring)


func _resolve_color(mode: String, val: String) -> Color:
	match mode:
		"Random":
			var p: String = Config.PALETTES.keys()[randi() % Config.PALETTES.size()]
			var arr: Array = Config.PALETTES[p]
			return arr[randi() % arr.size()]
		"Custom":
			# 与原版一致：选到不存在的名字不能崩，回退白色
			return Config.BASE_COLORS.get(val, Color8(255, 255, 255))
		_:
			var pal: Array = Config.PALETTES.get(val, Config.PALETTES["Neon"])
			return pal[randi() % pal.size()]


# ------------------------------------------------------------------ 信号回调

func _on_ball_bounced(point: Vector2, normal: Vector2, ring: Ring, speed: float) -> void:
	# 音效不受 `_fx` 是否就绪影响，所以先发声再判特效。
	if _audio != null:
		_audio.sfx_bounce(speed)
	if _fx == null or ring == null:
		return
	var dir: Vector2 = point - ring.global_position
	_fx.impact(point, dir.normalized() if dir != Vector2.ZERO else normal, ring.color)


## 小球从某个环的缺口穿出去了 —— 由**环自己的** `EscapeDetector`(`Area2D`) 判定后
## 发信号通知。这是物理事件（球心越过破环线），不是「球当前的位置看起来像在
## 环外」那种每帧谓词，所以不会漏判，也就不会出现「球穿过去了、环却不消失」。
func _on_ring_escaped(ring: Ring, at: Vector2, dir: Vector2) -> void:
	if _audio != null:
		_audio.sfx_ring_break()
	if _fx != null:
		_fx.ring_break_at(at, dir, Color8(255, 255, 255))
	ring.queue_free()
	# 通关判定不在这里做：`queue_free()` 是延迟的，此处 `_rings_root` 的
	# child_count 还没减少。见 `_process()`。


# --------------------------------------------------------------------- 结算

func _begin_settle() -> void:
	if state == State.SETTLE:
		return
	wins += 1
	state = State.SETTLE
	if _audio != null:
		_audio.sfx_celebration()
	if _fx != null:
		_fx.stop_trail()
	if _celebration != null:
		# 现在一切都在世界坐标里，直接把球的位置交给庆祝效果；
		# 不再需要 world_to_screen 换算。
		_celebration.play_at(_ball.global_position if _ball != null else Config.WORLD_CENTER)


func _finish_settle() -> void:
	if state != State.SETTLE:
		return
	# 离线渲染：录满 MOVIE_ROUNDS 局就收工，**在本局结算动画播完之后**退出，
	# 所以成片最后几秒是完整的庆祝画面，不会戛然而止。
	#
	# ⚠️ 必须走 `get_tree().quit()` 让引擎正常关闭 —— 只有这样
	#    `MovieWriter._write_end()` 才会被调用，写出带时长信息的可用文件。
	#    用 F8 / Ctrl+C 打断的话 AVI 会缺时长信息，剪辑软件打不开。
	if _movie_mode and wins >= Config.MOVIE_ROUNDS:
		print("[movie] 录制完成：%d 局，共 %d 帧 —— 正在写文件并退出"
				% [wins, Engine.get_frames_drawn()])
		get_tree().quit()
		return
	# ⚠️ 必须延到空闲帧再重开。本函数可能由 `PlayfieldLimiter` 的 `body_exited`
	# **物理信号**触发，而 `start_round()` 会建新环 —— 新环在 `_ready()` 里给
	# `CollisionPolygon2D.polygon` 赋值属于改物理状态。在物理查询刷写期间改它，
	# Godot 会报 "Can't change this state while flushing queries."，而且形状可能
	# 根本没注册上（环变成没有碰撞的空壳）。
	# 延迟后靠 `state` 自己兜重复调用：第一次跑完就变 PLAY，第二次直接返回。
	start_round.call_deferred(false)


func _on_celebration_finished() -> void:
	_finish_settle()


## 官方 Area2D 的 body_exited：小球离开游戏区（飞远了）。
func _on_ball_left_playfield(body: Node2D) -> void:
	if body != _ball:
		return
	if state == State.SETTLE:
		# 实时模式下不等结算动画播完 —— 球都飞出画面了，干等没意义。
		# 但离线渲染时那是**片尾**，提前收尾等于把庆祝镜头剪掉，所以照播不误。
		if _movie_mode and Config.MOVIE_FULL_CELEBRATION:
			return
		_finish_settle()
	elif state == State.PLAY:
		# 兜底：正常情况下球不可能在环还没碎完时飞出可见范围 —— 最外圈那个环
		# 会先被它撞碎，然后立刻进入结算。真发生了就重开一局，
		# 免得卡在「球已经在外面、环却还挂着」的死局里。
		# 同样是物理信号，所以也必须延迟。
		start_round.call_deferred(false)


# ------------------------------------------------------------------ UI 回调

func _on_start_game() -> void:
	_ui.set_menu_visible(false)
	start_round(true)


## UI 按钮点击音。滑块拖动**不**走这里（`value_changed` 会每帧连发，
## 那样会糊成噪音），只有按钮类的离散点击才发 `ui_click`。
func _on_ui_click() -> void:
	if _audio != null:
		_audio.sfx_ui_click()


func _on_apply_and_restart(cfg_from_ui: Dictionary) -> void:
	_ui.cfg = cfg_from_ui
	start_round(true)


func _on_exit_to_menu() -> void:
	state = State.MENU
	_clear_round()
	if _celebration != null:
		_celebration.finish_now()
	if _fx != null:
		_fx.stop_trail()
	_ui.set_menu_visible(true)
	_ui.set_wins(wins)

