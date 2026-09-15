extends Node2D
## 旋转圆环：一个带缺口的弧形环带。
##
## 设计要点（遵循 .dsh/skills 的「不要造轮子、优先官方节点」）：
##
## 1. **几何只有一份。** `_rebuild_geometry()` 生成唯一一份四边形列表，
##    同时喂给显示用的 `Polygon2D` 和碰撞用的 `ConvexPolygonShape2D`。
##    因此「画出来的环」和「能撞到球的环」在结构上不可能不一致。
##    此前的纯手写实现里渲染与碰撞各算一套几何，曾导致画出来的开口和物理开口
##    错开整整一个 gap（实测 55°），小球在看得见的实心处穿过去、在看得见的缺口
##    处反而被弹回来。
##
## 2. **为什么用逐段 `ConvexPolygonShape2D` 而不是一个 `CollisionPolygon2D`：**
##    环带是**非凸**且自交的闭合多边形，`CollisionPolygon2D` 的默认 `SOLIDS`
##    模式会把它交给 `Geometry2D.decompose_polygon_in_convex()` 做凸分解。
##    实测该分解对环带**不完整**：沿环带扫一圈，有的角度查到 2 个分块、有的
##    查到 0 个，于是球会从某些"实心"位置直接穿过去。
##    逐段凸四边形没有分解步骤，不存在失败的可能，而且每块天生凸。
##    （`SEGMENTS` 线段模式也不行：它只生成线，球会直接穿过，整条环带没有实体。）
##
## 3. **缺口就是碰撞几何里的一段空缺。** 球的 `move_and_collide()` 走到缺口处
##    自然没有碰撞、直接穿过；走到实心处自然拿到碰撞法线。无需任何角度判定。
##
## 4. **旋转交给节点 `rotation`。** 缺口的角宽度与环的朝向无关，所以纯旋转不改变
##    局部几何；只有 `angle_deg` 累计到一定程度才重建一次，用来消掉累计误差。

## 角度变化超过这个值才重建几何（度）。
const REBUILD_EPSILON := 0.01
## 旋转累计超过这个角度后，环重新变为「可击碎」（度）。
const BREAKABLE_ARC := 15.0
## 环带的角度细分段数。显示与碰撞都用它，所以两者逐段一致。
const ARC_SEGMENTS := 48
## 环心的世界坐标（pygame 原版的 V_CENTER）。
const WORLD_CENTER := Vector2(500.0, 500.0)

## 环中心线的世界半径（配置值，与 pygame 原版一致）。
var world_radius := 100.0
## 环带厚度（世界单位）。
var world_thickness := 14.0
## 世界→屏幕缩放。环的几何全部以屏幕像素存放，所以它参与运算。
var world_scale := 0.7
## 缺口角宽度（度）。
var gap_deg := 55.0
## 缺口起始朝向（度）。自转时持续累加。
var angle_deg := 0.0
## 自转角速度（度 / 物理帧）。
var spin := 0.0
## 球从本环缺口逃出去过之后才允许碎裂 —— 否则出生在环心就会被判成通关。
var escaped := false
var color := Color.WHITE

var _body: StaticBody2D
var _visual: Polygon2D
var _last_built_angle := INF
var _accum := 0.0
## 每段的碰撞形状，`_rebuild_geometry()` 逐个写入。
var _pieces: Array[ConvexPolygonShape2D] = []


## 工厂：创建并配置一个圆环。调用方负责 `add_child()`。
static func create(p_world_radius: float, p_scale: float, p_gap_deg: float,
		p_angle_deg: float, p_spin: float, p_color: Color) -> Node2D:
	var r: Node2D = (load("res://ring.tscn") as PackedScene).instantiate()
	r.world_radius = p_world_radius
	r.world_scale = p_scale
	r.gap_deg = p_gap_deg
	r.angle_deg = p_angle_deg
	r.spin = p_spin
	r.color = p_color
	return r


func _ready() -> void:
	_body = $SolidBody
	_visual = $Polygon2D
	_visual.antialiased = true
	# 加入分组，让球能发现所有环而不必持有引用（见 ball.gd check_escape）。
	add_to_group("rings")
	# 几何以「环心为原点」定义在局部空间，所以节点位置就是环心。
	position = WORLD_CENTER * world_scale
	rotation = deg_to_rad(angle_deg)
	_build_pieces()
	_rebuild_geometry()


## 一次性建好 ARC_SEGMENTS 个 CollisionShape2D，之后只更新形状数据。
## 不在每帧增删节点。
func _build_pieces() -> void:
	for i in range(ARC_SEGMENTS):
		var shape := ConvexPolygonShape2D.new()
		var cs := CollisionShape2D.new()
		cs.shape = shape
		_body.add_child(cs)
		_pieces.append(shape)


## 环带内边界半径（屏幕像素）—— 也是碰撞几何的内沿。
func inner_radius() -> float:
	return (world_radius - world_thickness * 0.5) * world_scale


## 环带外边界半径（屏幕像素）—— 也是碰撞几何的外沿。
func outer_radius() -> float:
	return (world_radius + world_thickness * 0.5) * world_scale


## 缺口的角度区间（度，已归一化到 [0,360)）。
func gap_span() -> Vector2:
	var s := fposmod(angle_deg, 360.0)
	return Vector2(s, fposmod(s + gap_deg, 360.0))


## 角度 a 是否在缺口内。缺口跨 0° 时（s > e）要绕回。
func angle_in_gap(a: float) -> bool:
	var span := gap_span()
	var s := span.x
	var e := span.y
	if s <= e:
		return a >= s and a <= e
	return a >= s or a <= e


## 半径 `radius`（局部像素）的球放在局部位置 `p` 时，是否**整个角度跨度**都在缺口内。
## 球的 `move_and_collide()` 已经保证它只能从真正的缺口空缺穿过；本函数用于判断
## 「球是否已经逃出这一环」，必须考虑球的半径 —— 否则球心刚过缺口边缘、球身还压
## 在实心段上就会被误判为逃出。
func gap_admits(p: Vector2, radius: float) -> bool:
	var d := maxf(p.length(), 0.001)
	var half := rad_to_deg(asin(clampf(radius / d, 0.0, 1.0)))
	var a := fposmod(rad_to_deg(atan2(p.y, p.x)), 360.0)
	return angle_in_gap(fposmod(a - half, 360.0)) and angle_in_gap(fposmod(a + half, 360.0))


func _physics_process(_delta: float) -> void:
	if spin != 0.0:
		angle_deg += spin
		rotation = deg_to_rad(angle_deg)
		# 环转过一段后重新可击碎：球可能先从这个缺口出去、又从别处撞回来。
		_accum += absf(spin)
		if _accum >= BREAKABLE_ARC:
			_accum = 0.0
			escaped = false
	if absf(angle_deg) >= 3600.0:
		angle_deg = fposmod(angle_deg, 360.0)
		_last_built_angle = INF
	# 局部几何与朝向无关，只有累计误差需要偶尔消一次。
	if absf(angle_deg - _last_built_angle) > REBUILD_EPSILON:
		_rebuild_geometry()


## 生成环带几何 —— **显示与碰撞共用的唯一一份数据**。
##
## 每段是一个凸四边形（内弧两点 + 外弧两点），相邻段共端点，首尾不闭合，
## 缺口处自然留空。
func _rebuild_geometry() -> void:
	var span := gap_span()
	var start_rad := deg_to_rad(span.y)
	var sweep_rad := deg_to_rad(360.0 - gap_deg)
	var ri := inner_radius()
	var ro := outer_radius()
	var n := ARC_SEGMENTS
	# 显示用：整条环带一个多边形（外弧正向 + 内弧反向）
	var display := PackedVector2Array()
	display.resize((n + 1) * 2)
	for i in range(n + 1):
		var a := start_rad + sweep_rad * float(i) / float(n)
		var dir := Vector2(cos(a), sin(a))
		display[i] = dir * ro
		display[(n + 1) * 2 - 1 - i] = dir * ri
	_visual.polygon = display
	_visual.color = color
	# 碰撞用：每段一个凸四边形，顺序保持 CCW（与显示多边形同向）
	for i in range(n):
		var a0 := start_rad + sweep_rad * float(i) / float(n)
		var a1 := start_rad + sweep_rad * float(i + 1) / float(n)
		var d0 := Vector2(cos(a0), sin(a0))
		var d1 := Vector2(cos(a1), sin(a1))
		var quad := PackedVector2Array([
			d0 * ri, d1 * ri, d1 * ro, d0 * ro])
		_pieces[i].points = quad
	_last_built_angle = angle_deg
