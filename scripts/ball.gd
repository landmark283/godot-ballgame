class_name Ball
extends CharacterBody2D
## 小球：用 Godot 官方的 `CharacterBody2D` + `move_and_collide()` 运动与反弹。
##
## 所有可调参数集中在 `scripts/config.gd`（`Config.BALL_*` / `Config.WORLD_*`），
## 本文件只管逻辑。
##
## 为什么是 `move_and_collide()` 而不是 `move_and_slide()`：
## 本作是台球/弹球式的运动，需要拿到精确的 `KinematicCollision2D` 法线来做
## 镜面反弹，不需要贴墙滑行、斜坡、地板吸附等角色控制特性。
##
## 速度单位是「世界单位 / 物理帧」，与 pygame 原版逐行对应：
## 原版每帧做 10 次 `v_pos += v_vel / 10`，等价于每帧位移 `v_vel`。
## 原版那 10 次子步循环由引擎的连续碰撞检测取代 —— `move_and_collide()`
## 一次调用就扫掠整段位移。
##
## 位置、半径、位移**全部是世界单位**，不含任何屏幕缩放：
## 世界→屏幕由 `Camera2D.zoom` 统一承担（见 `main.gd::_sync_camera()`）。
## 旧版在这里乘了一次 `world_scale`（几何也乘一次、相机又 zoom 一次），
## 缩放被叠了三层，盘面因此只占画面宽的 33%。
##
## 球**不**负责判断「有没有从某个环逃出去」：那是环自己的 `EscapeDetector`
## (`Area2D`) 发出的物理事件，球只需把自己的位置更新好。
## 旧实现让球每帧反查所有环、用几何谓词判断逃出，既贵又会漏判
## （原因见 `ring.gd` 顶部注释）。

## 撞到环的实心处。`contact_point` / `normal` 都是**世界坐标**。
##
## `speed` 是**撞击前**的速度大小（世界单位 / 物理帧），用来给音效与特效分级：
## 撞得狠 → 音更高更响。必须取反弹**之前**的值 —— 弹完再读，`BALL_RESTITUTION`
## 会把它按 0.98 缩掉一点点，而且语义上也变成了「弹开后的速度」。
signal bounced(contact_point: Vector2, normal: Vector2, ring: Ring, speed: float)

## 重力（世界单位 / 物理帧²），由 main 从 `DEFAULT_CFG.gravity` 写入。
var gravity_per_tick := Config.BALL_GRAVITY
## 「速度过小就加速」的阈值（世界单位 / 物理帧）。
var min_speed := Config.BALL_MIN_SPEED

var color := Color.WHITE

var _shape: CollisionShape2D
var _visual: Polygon2D


func _ready() -> void:
	_shape = $CollisionShape2D
	_visual = $Polygon2D
	_apply_radius()


## 写入球形碰撞半径，并重建显示圆。
## 只改 `CircleShape2D.radius`，**不去缩放 `CollisionShape2D` 节点** ——
## 缩放碰撞体节点会让法线与接触点失真（2D 物理的反模式）。
func _apply_radius() -> void:
	var r := Config.BALL_WORLD_RADIUS
	(_shape.shape as CircleShape2D).radius = r
	_visual.color = color
	var pts := PackedVector2Array()
	pts.resize(Config.BALL_CIRCLE_STEPS)
	for i in range(Config.BALL_CIRCLE_STEPS):
		pts[i] = Vector2.from_angle(TAU * float(i) / float(Config.BALL_CIRCLE_STEPS)) * r
	_visual.polygon = pts


## 重置到盘面中心并给一个初始速度，与原版 `Ball.__init__` 对应。
func launch(center: Vector2, vx: float, vy: float) -> void:
	global_position = center
	velocity = Vector2(vx, vy)


func _physics_process(delta: float) -> void:
	velocity.y += gravity_per_tick
	if velocity.length() < min_speed:
		velocity *= Config.BALL_MIN_SPEED_MULT

	# 位移是世界单位，乘 delta 以适配任意物理 tick 频率。
	# （`move_and_collide` / `move_and_slide` 不会自己乘 delta，必须显式乘。）
	var dist := velocity * delta * Engine.physics_ticks_per_second
	var col := move_and_collide(dist)
	if col != null:
		_handle_collision(col)


func _handle_collision(col: KinematicCollision2D) -> void:
	# 撞击力度取反弹**之前**的速度大小（见 signal bounced 的说明）。
	var speed := velocity.length()
	# 官方 Vector2.bounce() 即标准镜面反射 v - 2(v·n)n。
	# ⚠️ 不要用 Vector2.reflect()：Godot 的 reflect 翻的是切向分量，且忽略法线
	#    正负号，会让球继续往外飞、永远弹不回来。
	velocity = velocity.bounce(col.get_normal()) * Config.BALL_RESTITUTION
	var collider := col.get_collider()
	if collider is StaticBody2D and collider.get_parent() is Ring:
		# `get_position()` / `get_normal()` 都是**世界坐标**，直接往外传即可。
		bounced.emit(col.get_position(), col.get_normal(),
				collider.get_parent() as Ring, speed)
