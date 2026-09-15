class_name Ring
extends Node2D
## 旋转圆环：一段带缺口的弧带。场景结构见 `ring.tscn`。
##
## 所有可调参数集中在 `scripts/config.gd`（`Config.RING_*` / `Config.WORLD_*`），
## 本文件只管逻辑。
##
## 环有**两个各司其职的碰撞子节点**，节点本身写在场景里，形状由脚本按
## 半径 / 缺口写入 —— 所以场景在编辑器里打开就是完整可检视、无警告的：
##
## * `SolidBody`（`StaticBody2D`）—— **反弹**。
##   弧带被切成 `Config.RING_ARC_CHUNKS` 个**简单**（非自交）扇段，每段一个官方
##   `CollisionPolygon2D`（`BUILD_SOLIDS`），凸分解交给引擎自带的
##   `Geometry2D.decompose_polygon_in_convex()`，不再自己手切凸块。
##   缺口就是这条弧带上**真的缺了一段**。
##
## * `EscapeDetector`（`Area2D`）—— **逃出判定**，判定结果就是「碎环」。
##   一个贴在弧带外侧的**整圈**环壳，内沿半径取「破环线 + 球半径」，
##   于是 `body_entered` 恰好等价于
##   「球的**圆心**越过破环线」，与 pygame 原版 `dist > r + thickness/3` 对应。
##
## ## 为什么探测区是整圈，而不是只盖住缺口角度
##
## 因为**角度条件正是最初的 bug 来源**，两道都不该再留：
##
## 1. 缺口本身已经由 `SolidBody` 的几何强制了 —— 那里**真的是个洞**。
##    球要从环内到环外，只能走这个洞。所以「越过破环线」已经蕴含「从缺口穿出」，
##    再叠一层角度谓词是多余的。
## 2. 叠了角度就会漏判。实测（半径 70px 的环、`gap=55°`）：球心越过破环线时，
##    它在环局部系里的角度可以落在缺口外 8° 以上 —— 靠近外沿时球身只在环带上
##    蹭掉一小片，几何上**允许**球心偏出缺口很多。角度窗口开多大都不够。
##
## 旧实现（球每帧用几何谓词判断逃出）栽在同一个坑里：球穿出那一帧角度常贴着
## 缺口边缘，判据当场为假，之后球越飞越远、判据长期为假 —— 于是「球明明穿过了环、
## 环却一直不消失」，又因为 `main._process()` 要求环全清才结算，整局永久卡死。
##
## ## 几何只构建一次
##
## 局部几何不随朝向变化，自转完全交给节点 `rotation`。
## 旧实现在重建函数里又把 `angle_deg` 写进局部顶点，与节点旋转叠加，
## **观感转速是配置值的 2 倍**，还每帧重写一次全部形状。现在两者都没有了。
##
## ## 顶点是**世界单位**，不含任何屏幕缩放
##
## 世界→屏幕统一由 `Camera2D.zoom` 承担（见 `main.gd::_sync_camera()`）。
## 这样改分辨率 / 改版式都不用重建 `ring.tscn`，也不会出现「缩放乘两遍」。

## 球从本环缺口穿出去了。`at` 是球当时的世界坐标，`dir` 是背离环心的单位向量。
signal escaped(ring: Ring, at: Vector2, dir: Vector2)

## 环心线的世界半径。
var world_radius := Config.RING_FIRST_WORLD_RADIUS
## 弧带厚度（世界单位）。
var world_thickness := Config.RING_WORLD_THICKNESS
## 缺口角宽度（度）。
var gap_deg := Config.RING_GAP_DEG
## 缺口朝向（度）。只在自转时累加，仅影响节点 `rotation`。
var angle_deg := 0.0
## 自转角速度（度 / 物理帧）。实际会被 `Config.RING_MAX_SWEEP_HALF_THICKNESS` 夹住。
var spin := 0.0
## 球的半径（世界单位）。探测环壳按它外扩，`body_entered` 才能对上球**圆心**的位置。
var ball_radius := Config.BALL_WORLD_RADIUS
var color := Color.WHITE

var _escaped := false


func _ready() -> void:
	# 几何以「环心为原点」定义在局部空间，所以节点位置就是环心。
	# ⚠️ 这里**不要**再乘任何缩放：几何已经是世界单位，缩放由相机 zoom 统一承担。
	#    旧版写成 `WORLD_CENTER * world_scale`，既和相机的 `WORLD_CENTER` 错开
	#    150 世界单位（画面偏心 105px），又把缩放乘了第二遍。
	position = Config.WORLD_CENTER
	rotation = deg_to_rad(angle_deg)
	_apply_geometry()
	# 掩码已经限定只探测球那一层，回调里不必再判类型。
	($EscapeDetector as Area2D).body_entered.connect(_on_escaped_body)


## 把 `build_geometry()` 的唯一一份顶点喂给显示与两个碰撞节点。
func _apply_geometry() -> void:
	var arcs := _poly_children($SolidBody)
	var geo := build_geometry(world_radius, world_thickness, gap_deg,
			ball_radius, arcs.size())
	var visual := $Visual as Polygon2D
	visual.polygon = geo["visual"]
	visual.color = color
	var sectors: Array = geo["sectors"]
	for i in range(mini(arcs.size(), sectors.size())):
		(arcs[i] as CollisionPolygon2D).polygon = sectors[i]
	var shells := _poly_children($EscapeDetector)
	var ring_shells: Array = geo["shells"]
	for i in range(mini(shells.size(), ring_shells.size())):
		(shells[i] as CollisionPolygon2D).polygon = ring_shells[i]


## 某个碰撞节点下实际存在的 CollisionPolygon2D 子节点，顺序即几何顺序。
## 数量以**场景**为准而不是一个常量，改场景不必同步改代码。
func _poly_children(parent: Node) -> Array[CollisionPolygon2D]:
	var out: Array[CollisionPolygon2D] = []
	for c in parent.get_children():
		if c is CollisionPolygon2D:
			out.append(c)
	return out


## 弧带外沿半径（世界单位）。
func outer_radius() -> float:
	return outer_world_radius(world_radius, world_thickness)


## 给定环心线半径与厚度时的外沿半径（世界单位）。
## 静态版给 `main` 算取景用 —— 那时还没有环实例。
static func outer_world_radius(p_world_radius: float, p_thickness: float) -> float:
	return p_world_radius + p_thickness * 0.5


func _physics_process(_delta: float) -> void:
	if spin == 0.0:
		return
	# 把「度 / 物理帧」夹到「每帧切向扫掠 ≤ budget」。
	# 见 Config.RING_MAX_SWEEP_HALF_THICKNESS 里对原因与实测的记录。
	# 两边的量纲现在都是世界单位，比值与旧版一致（旧版两边同乘 world_scale）。
	var budget := world_thickness * 0.5 * Config.RING_MAX_SWEEP_HALF_THICKNESS
	var max_spin := rad_to_deg(budget / maxf(outer_radius(), 1.0))
	angle_deg += clampf(spin, -max_spin, max_spin)
	rotation = deg_to_rad(angle_deg)
	# 单纯防止浮点精度无限增长；wrap 前后 `rotation` 不变（几何与朝向无关）。
	if absf(angle_deg) >= 3600.0:
		angle_deg = fposmod(angle_deg, 360.0)


## 球心越过破环线 —— 环碎。缺口由 `SolidBody` 的几何保证，无需角度判定。
func _on_escaped_body(body: Node2D) -> void:
	if _escaped:
		return
	_escaped = true
	var at := body.global_position
	escaped.emit(self, at, (at - global_position).normalized())


# ------------------------------------------------------------------ 几何

## 生成环的全部几何：**显示多边形、弧带扇段、探测环壳共用同一批角度**。
##
## 这是环几何的唯一来源。显示节点与两个碰撞节点都从这一份数据取数，从结构上
## 排除「画出来的」与「能撞到的」不一致 —— 旧实现两边各算一套，曾导致
## 画出来的缺口和物理缺口错开整整一个 `gap`（实测 55°），球在看得见的实心处
## 穿过去、在看得见的缺口处反而被弹回来；另一版则让碰撞带比画出来的宽 3.9 倍。
##
## `tools/build_ring_scene.gd` 也用本函数生成 `ring.tscn`，所以场景里的预览
## 几何和运行时几何不可能对不上。
##
## 局部坐标下缺口固定落在 `[0, p_gap]`，朝向由节点 `rotation` 承担。
static func build_geometry(p_world_radius: float, p_thickness: float,
		p_gap: float, p_ball_radius: float, p_chunks: int) -> Dictionary:
	var ri := p_world_radius - p_thickness * 0.5
	var ro := p_world_radius + p_thickness * 0.5
	var start := deg_to_rad(p_gap)
	var sweep := deg_to_rad(360.0 - p_gap)
	var inner := PackedVector2Array()
	var outer := PackedVector2Array()
	for k in range(Config.RING_ARC_SEGMENTS + 1):
		var d := Vector2.from_angle(start + sweep * float(k) / float(Config.RING_ARC_SEGMENTS))
		inner.append(d * ri)
		outer.append(d * ro)

	# 显示：外弧正向 + 内弧反向，围成整条弧带。
	var visual := outer.duplicate()
	for k in range(Config.RING_ARC_SEGMENTS, -1, -1):
		visual.append(inner[k])

	# 碰撞：同一批顶点按扇段切开成若干**简单**多边形。
	var chunks := maxi(1, p_chunks)
	var sectors: Array[PackedVector2Array] = []
	for c in range(chunks):
		var k0 := int(round(float(Config.RING_ARC_SEGMENTS) * float(c) / float(chunks)))
		var k1 := int(round(float(Config.RING_ARC_SEGMENTS) * float(c + 1) / float(chunks)))
		var poly := PackedVector2Array()
		for k in range(k0, k1 + 1):
			poly.append(outer[k])
		for k in range(k1, k0 - 1, -1):
			poly.append(inner[k])
		sectors.append(poly)

	# 逃出探测区：贴着弧带外侧的**整圈**环壳，内沿 = 破环线 + 球半径。
	# 整圈是刻意的，理由见文件头「为什么探测区是整圈」；环壳要**厚**，
	# 因为解算把球弹出去时是一步跳很远，薄壳会被整个跨过去。
	var s_in := p_world_radius + p_thickness * Config.RING_BREAK_BIAS + p_ball_radius
	var s_out := s_in + p_ball_radius * Config.RING_SHELL_RADIAL_BALL_RADII
	var shells: Array[PackedVector2Array] = []
	var nch := maxi(2, chunks)
	for c in range(nch):
		var m0 := int(round(float(Config.RING_ARC_SEGMENTS) * float(c) / float(nch)))
		var m1 := int(round(float(Config.RING_ARC_SEGMENTS) * float(c + 1) / float(nch)))
		var shell := PackedVector2Array()
		for k in range(m0, m1 + 1):
			shell.append(Vector2.from_angle(
					TAU * float(k) / float(Config.RING_ARC_SEGMENTS)) * s_out)
		for k in range(m1, m0 - 1, -1):
			shell.append(Vector2.from_angle(
					TAU * float(k) / float(Config.RING_ARC_SEGMENTS)) * s_in)
		shells.append(shell)

	return {"visual": visual, "sectors": sectors, "shells": shells}
