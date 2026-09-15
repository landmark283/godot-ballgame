extends CharacterBody2D
## 小球：用 Godot 官方的 `CharacterBody2D` + `move_and_collide()` 运动与反弹。
##
## 为什么是 `move_and_collide()` 而不是 `move_and_slide()`：
## 本作是台球/弹球式的运动，需要拿到精确的 `KinematicCollision2D` 法线来
## 做镜面反弹，不需要贴墙滑行、斜坡、地板吸附等角色控制特性。
##
## 速度单位是「世界单位 / 物理帧」，与 pygame 原版逐行对应：
## 原版每帧做 10 次 `v_pos += v_vel / 10`，等价于每帧位移 `v_vel`。
## 这里把 `v_vel` 乘上 `world_scale` 换成屏幕像素后交给引擎。
## 逐行原版实现被替换成了引擎的连续碰撞检测（`move_and_collide` 会在
## 一次调用内扫掠整段位移），因此不再需要手写子步循环。
##
## 经过环带时不再需要任何角度判定：环的缺口就是它碰撞几何里的一个洞，
## 引擎在缺口处自然不产生碰撞。

signal bounced(contact_point: Vector2, normal: Vector2, ring: Node2D)
## 球从某个环的缺口整个逃出去了。参数是该环的外沿半径。
signal escaped_ring(ring: Node2D, outer_radius: float)

## 世界单位 → 屏幕像素的缩放，由 main 在配置阶段写入。
var world_scale := 0.7
## 重力（世界单位 / 物理帧²），与 pygame 原版的 gravity/10 对应。
var gravity_per_tick := 0.02
## 「速度过小就加速」的世界单位阈值。原版按像素尺度取 1.0，这里也要换算，
## 否则正常速度会被误判为「过小」并每帧被放大。
var min_speed := 1.0

## 碰撞后保留的速度比例（原版为 0.98）。
const RESTITUTION := 0.98
## 速度过小时加速，避免球停死（原版 `v_vel.length() < 1.0` 时 `* 1.1`）。
##
## ⚠️ 阈值必须与**像素/帧**同尺度。原版直接拿像素速度比较 1.0；本实现内部速度
## 是世界单位/物理帧，如果沿用 1.0 会让正常速度（≈3 世界单位）每帧都低于阈值、
## 每帧乘 1.1，速度指数爆炸（实测 3000 帧后半径涨到 18 万像素）。
## 所以阈值定义在世界单位下，由 main 一并写入。
const MIN_SPEED_MULT := 1.1
## 球半径（世界单位）。
const WORLD_RADIUS := 12.0
## 显示用圆的细分段数。
const CIRCLE_STEPS := 32
## 圆环节点所在的分组。球通过分组发现环，不需要持有环的引用。
const RING_GROUP := "rings"

var _shape: CollisionShape2D
var _visual: Polygon2D
var color := Color.WHITE


func _ready() -> void:
	_shape = $CollisionShape2D
	_visual = $Polygon2D
	_apply_radius()


## 按 `world_scale` 写入球形碰撞半径，并重建显示圆。
## 只改 `CircleShape2D.radius`，**不去缩放 `CollisionShape2D` 节点** ——
## 缩放碰撞体节点会让法线与接触点失真（2D 物理的反模式）。
func _apply_radius() -> void:
	var px := WORLD_RADIUS * world_scale
	(_shape.shape as CircleShape2D).radius = px
	_visual.color = color
	var pts := PackedVector2Array()
	pts.resize(CIRCLE_STEPS)
	for i in range(CIRCLE_STEPS):
		var a := TAU * float(i) / float(CIRCLE_STEPS)
		pts[i] = Vector2(cos(a), sin(a)) * px
	_visual.polygon = pts


## 重置到世界中心并给一个初始速度，与原版 `Ball.__init__` 对应。
func launch(center: Vector2, vx: float, vy: float) -> void:
	global_position = center * world_scale
	velocity = Vector2(vx, vy)


func _physics_process(delta: float) -> void:
	velocity.y += gravity_per_tick
	if velocity.length() < min_speed:
		velocity *= MIN_SPEED_MULT

	# 位移换算成屏幕像素，并乘上 delta 以适配任意 physics tick 频率。
	# （move_and_collide / move_and_slide 不会自己乘 delta，必须显式乘。）
	var dist := velocity * world_scale * delta * Engine.physics_ticks_per_second
	var col := move_and_collide(dist)
	if col != null:
		_handle_collision(col)
	# 移动之后再判断「是否从某个环的缺口整个穿出去了」。
	# 用 get_tree().get_nodes_in_group 而不是自己维护列表：环由 main 动态增删，
	# 分组让球不必知道环存在哪里（信号驱动的松耦合）。
	for node in get_tree().get_nodes_in_group(RING_GROUP):
		check_escape(node)


func _handle_collision(col: KinematicCollision2D) -> void:
	var n := col.get_normal()
	# 官方 Vector2.bounce() 即标准镜面反射 v - 2(v·n)n。
	# ⚠️ 不要用 Vector2.reflect()：Godot 的 reflect 翻的是切向分量，
	#    且忽略法线正负号，会让球继续往外飞、永远弹不回来。
	velocity = velocity.bounce(n) * RESTITUTION
	var point := col.get_position()
	# 碰撞体是环的 SolidBody；对外暴露环节点本身，main 才能直接用它做特效。
	var collider := col.get_collider()
	if collider is Node:
		var ring := (collider as Node).get_parent() if (collider as Node).name == "SolidBody" else collider
		bounced.emit(point, n, ring)


## 由 main 在球移动到新位置后调用：判断球是否整个穿出了某个环的缺口。
## 环负责提供「缺口能否容下这个半径的球」这一判断，球只提供位置与半径。
func check_escape(ring: Node2D) -> void:
	if ring.escaped:
		return
	var local := ring.to_local(global_position)
	var d := local.length()
	if d <= ring.outer_radius():
		return
	var admits: bool = ring.gap_admits(local, WORLD_RADIUS * world_scale)
	if not admits:
		return
	ring.escaped = true
	escaped_ring.emit(ring, ring.outer_radius())
