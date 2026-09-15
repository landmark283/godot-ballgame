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

const UI_SCENE := "res://ui.tscn"
const RING_SCENE := "res://ring.tscn"
const BALL_SCENE := "res://ball.tscn"

## 世界→屏幕缩放（与 pygame 原版一致）。
const WORLD_SCALE := 0.7
## 环心世界坐标（pygame 原版的 V_CENTER）。
const WORLD_CENTER := Vector2(500.0, 500.0)
const BALL_WORLD_RADIUS := 12.0
const RING_WORLD_THICKNESS := 14.0
## 侧栏宽度，用于把世界中心摆到可见区域中央。
const SIDEBAR_W := 300.0

const DEFAULT_CFG := {
	"rings_count": 8, "rotation_speed": 1.8, "gap_size": 55, "gravity": 0.2,
	"ring_mode": "Random", "ring_val": "Neon", "ball_mode": "Random", "ball_val": "Gold",
}

## 环被小球撞碎。
signal ring_broken(ring: Node2D, at: Vector2, dir: Vector2)

enum State { MENU, PLAY, SETTLE }

var state := State.MENU
var wins := 0
var cfg := DEFAULT_CFG.duplicate()

var _camera: Camera2D
var _rings_root: Node2D
var _ball: CharacterBody2D
## 已经碎掉、正在等待释放的环。用**按环记录**而不是一个全局布尔闩锁 ——
## 全局闩锁会让第一环碎掉之后所有环都不再碎（实测 900 帧 0 环被击碎）。
var _pending_break := {}

@onready var _fx: Node2D = $ParticleFX
@onready var _celebration: Node2D = $CelebrationFX
@onready var _limiter: Area2D = $PlayfieldLimiter
@onready var _ui: CanvasLayer = $UI


func _ready() -> void:
	_camera = $World/Camera2D
	_rings_root = $World/Rings
	_ui.start_game.connect(_on_start_game)
	_ui.apply_and_restart.connect(_on_apply_and_restart)
	_ui.exit_to_menu.connect(_on_exit_to_menu)
	ring_broken.connect(_on_ring_broken)
	_celebration.finished.connect(_on_celebration_finished)
	_limiter.body_exited.connect(_on_ball_left_playfield)
	_fx.stop_trail()
	_celebration.visible = false
	_ui.set_wins(wins)
	_sync_camera()
	_sync_limiter()


## 「球已飞出可见范围」判定区。用官方 `Area2D` 的 `body_exited` 信号，
## 而不是自己每帧算矩形包含 —— 判定范围也会随视口与侧栏变化，所以在
## `_process` 里同步（`_process` 每帧都跑，视口尺寸变化自然被跟上）。
##
## 尺寸取「视口能容纳的世界范围」再放宽 1.6 倍：太紧会在球还看得见时就判出界，
## 太松则要等很久。
func _sync_limiter() -> void:
	var vp := Vector2(get_viewport_rect().size)
	var span := vp / WORLD_SCALE * 1.6
	var shape := ($PlayfieldLimiter/CollisionShape2D as CollisionShape2D).shape as RectangleShape2D
	if shape != null:
		shape.size = span
	($PlayfieldLimiter as Area2D).position = WORLD_CENTER * WORLD_SCALE


func _process(_delta: float) -> void:
	# 侧栏显隐会改变世界中心在屏幕上的位置，只需更新相机偏移。
	_sync_camera()
	_sync_limiter()
	_ui.set_wins(wins)
	# `queue_free()` 要到帧末才真正把环移出树，所以碎裂当帧 child_count 仍非 0。
	# 通关判定放在这里等它真正清空，而不是在信号回调里抢答。
	if state == State.PLAY and _rings_root.get_child_count() == 0 and _ball != null:
		_begin_settle()


## 把世界中心摆到「可见游戏区」的正中：侧栏占去右侧 SIDEBAR_W 像素，所以整个
## 世界要往左移半个侧栏宽。Camera2D 的 offset 是屏幕像素，除以 zoom 换成世界单位。
func _sync_camera() -> void:
	var zoom := WORLD_SCALE
	_camera.zoom = Vector2(zoom, zoom)
	var sidebar_on: bool = _ui.sidebar_visible() and state != State.MENU
	var shift_px := -SIDEBAR_W * 0.5 if sidebar_on else 0.0
	_camera.offset = Vector2(-shift_px / zoom, 0.0)


# --------------------------------------------------------------------- 开局

func start_round(apply_cfg: bool = false) -> void:
	if apply_cfg:
		cfg = _ui.cfg.duplicate()
	_clear_round()
	_spawn_ball()
	_spawn_rings()
	_pending_break.clear()
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
	_ball = (load(BALL_SCENE) as PackedScene).instantiate()
	_ball.world_scale = WORLD_SCALE
	# 原版每帧 10 次子步、每次重力 gravity/10，所以每帧重力增量就是 gravity。
	_ball.gravity_per_tick = float(cfg["gravity"])
	# 原版按「世界单位/帧」比较 1.0，这里保持同一尺度。
	_ball.min_speed = 1.0
	_ball.color = _resolve_color(String(cfg["ball_mode"]), String(cfg["ball_val"]))
	_ball.bounced.connect(_on_ball_bounced)
	_ball.escaped_ring.connect(_on_ball_escaped_ring)
	$World.add_child(_ball)
	var vx: float = [-5.0, 5.0][randi() % 2]
	_ball.launch(WORLD_CENTER, vx, randf_range(-3.0, 3.0))


func _spawn_rings() -> void:
	var count: int = int(cfg["rings_count"])
	for i in range(count):
		var spin: float = [-1.0, 1.0][randi() % 2] * float(cfg["rotation_speed"])
		var ring: Node2D = (load(RING_SCENE) as PackedScene).instantiate()
		ring.world_radius = 100.0 + i * 50.0
		ring.world_thickness = RING_WORLD_THICKNESS
		ring.world_scale = WORLD_SCALE
		ring.gap_deg = float(cfg["gap_size"])
		ring.angle_deg = randf_range(0.0, 360.0)
		ring.spin = spin
		ring.color = _resolve_color(String(cfg["ring_mode"]), String(cfg["ring_val"]))
		_rings_root.add_child(ring)


func _resolve_color(mode: String, val: String) -> Color:
	match mode:
		"Random":
			var p: String = UI_PALETTES.keys()[randi() % UI_PALETTES.size()]
			var arr: Array = UI_PALETTES[p]
			return arr[randi() % arr.size()]
		"Custom":
			# 与原版一致：选到不存在的名字不能崩，回退白色
			return UI_BASE_COLORS.get(val, Color8(255, 255, 255))
		_:
			var pal: Array = UI_PALETTES.get(val, UI_PALETTES["Neon"])
			return pal[randi() % pal.size()]


# ------------------------------------------------------------------ 信号回调

func _on_ball_bounced(point: Vector2, normal: Vector2, ring: Node2D) -> void:
	if _fx == null or ring == null:
		return
	var dir: Vector2 = point - ring.global_position
	_fx.impact(point, dir.normalized() if dir != Vector2.ZERO else normal, ring.color)


func _on_ball_escaped_ring(ring: Node2D, _outer_radius: float) -> void:
	if ring == null or _pending_break.has(ring):
		return
	_pending_break[ring] = true
	var dir: Vector2 = _ball.global_position - ring.global_position
	ring_broken.emit(ring, _ball.global_position, dir.normalized())
	ring.queue_free()


func _on_ring_broken(_ring: Node2D, at: Vector2, dir: Vector2) -> void:
	if _fx != null:
		_fx.ring_break_at(at, dir, Color8(255, 255, 255))
	# 通关判定不在这里做：queue_free() 是延迟的，此处 child_count 还没减少。
	# 见 _process()。


# --------------------------------------------------------------------- 结算

func _begin_settle() -> void:
	if state == State.SETTLE:
		return
	wins += 1
	state = State.SETTLE
	if _fx != null:
		_fx.stop_trail()
	if _celebration != null:
		# 现在一切都在世界坐标里，直接把球的位置交给庆祝效果；
		# 不再需要 world_to_screen 换算。
		_celebration.play_at(_ball.global_position if _ball != null else WORLD_CENTER)


func _finish_settle() -> void:
	if state != State.SETTLE:
		return
	start_round(false)


func _on_celebration_finished() -> void:
	_finish_settle()


## 官方 Area2D 的 body_exited：小球离开游戏区（飞远了）→ 结束结算，开下一局。
func _on_ball_left_playfield(body: Node2D) -> void:
	if body == _ball:
		_finish_settle()


# ------------------------------------------------------------------ UI 回调

func _on_start_game() -> void:
	_ui.set_menu_visible(false)
	start_round(true)


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


# ------------------------------------------------------------------ 配色表
# 与 ui.gd 保持一致：随机/调色板取色用。

const UI_PALETTES := {
	"Neon": [Color8(0, 255, 255), Color8(0, 150, 255), Color8(150, 50, 255), Color8(255, 0, 255), Color8(0, 255, 100)],
	"Fire": [Color8(255, 50, 0), Color8(255, 120, 0), Color8(255, 200, 50), Color8(200, 0, 0)],
	"Cyber": [Color8(255, 0, 150), Color8(100, 0, 255), Color8(0, 255, 200), Color8(50, 0, 150)],
	"Ocean": [Color8(0, 50, 200), Color8(0, 150, 255), Color8(100, 200, 255), Color8(0, 255, 180)],
	"Forest": [Color8(50, 255, 50), Color8(0, 150, 50), Color8(150, 255, 100)],
	"Pastel": [Color8(255, 180, 180), Color8(180, 255, 180), Color8(180, 180, 255)],
}

const UI_BASE_COLORS := {
	"Cyan": Color8(0, 255, 255), "Red": Color8(255, 50, 50), "Green": Color8(50, 255, 50),
	"Gold": Color8(255, 215, 0), "Pink": Color8(255, 100, 255), "White": Color8(255, 255, 255),
	"Orange": Color8(255, 140, 0), "Purple": Color8(150, 0, 255), "Lime": Color8(180, 255, 0),
	"Blue": Color8(0, 100, 255), "Mint": Color8(170, 255, 195), "Crimson": Color8(220, 20, 60),
}
