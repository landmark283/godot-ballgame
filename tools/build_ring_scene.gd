extends SceneTree
## 生成 `ring.tscn`。
##
## 为什么需要生成而不是手写：环的碰撞形状是「弧带扇段」和「逃出探测环壳」两组
## 多边形，顶点数近 400 个。手抄数字必然出错，所以让它直接调用
## `ring.gd::build_geometry()` —— 和运行时**同一份**算法，不可能对不上。
##
## 场景里烤进去的是 `Config` 默认参数下的几何（半径 / 厚度 / 缺口全部取自
## `scripts/config.gd`），只是给编辑器看的预览与占位；运行时 `_apply_geometry()`
## 会按每环的实际半径/缺口重写。这样场景在编辑器里打开就是完整、可检视、无警告的。
##
## 顶点是**世界单位**，不含屏幕缩放 —— 缩放由相机 zoom 承担，所以改分辨率/版式
## 不需要重跑本脚本；只有几何参数（半径 / 厚度 / 缺口 / 细分 / 球半径）变了才要。
##
## 用法（改了 `Config` 里的几何参数、或改了 `build_geometry()` 之后要重跑）：
##   godot --headless --path godot-ballgame --script res://tools/build_ring_scene.gd

const SCRIPT_PATH := "res://scripts/ring.gd"


func _initialize() -> void:
	var ring_script := load(SCRIPT_PATH) as GDScript
	if ring_script == null:
		push_error("加载不到 " + SCRIPT_PATH)
		quit(1)
		return
	# 默认参数与运行时完全同一份来源。
	var geo: Dictionary = ring_script.build_geometry(
			Config.RING_FIRST_WORLD_RADIUS,
			Config.RING_WORLD_THICKNESS,
			Config.RING_GAP_DEG,
			Config.BALL_WORLD_RADIUS,
			Config.RING_ARC_CHUNKS)

	var t := "[gd_scene load_steps=2 format=3]\n\n"
	t += "[ext_resource type=\"Script\" path=\"%s\" id=\"1_ring\"]\n\n" % SCRIPT_PATH

	t += "[node name=\"Ring\" type=\"Node2D\"]\n"
	t += "script = ExtResource(\"1_ring\")\n\n"

	t += "[node name=\"Visual\" type=\"Polygon2D\" parent=\".\"]\n"
	t += "antialiased = true\n"
	t += "color = Color(1, 1, 1, 1)\n"
	t += "polygon = %s\n\n" % _pv(geo["visual"])

	t += "[node name=\"SolidBody\" type=\"StaticBody2D\" parent=\".\"]\n"
	t += "collision_layer = 2\n"
	t += "collision_mask = 1\n\n"

	var sectors: Array = geo["sectors"]
	for i in range(sectors.size()):
		t += "[node name=\"Arc%d\" type=\"CollisionPolygon2D\" parent=\"SolidBody\"]\n" % i
		t += "polygon = %s\n\n" % _pv(sectors[i])

	t += "[node name=\"EscapeDetector\" type=\"Area2D\" parent=\".\"]\n"
	t += "collision_layer = 0\n"
	t += "collision_mask = 1\n\n"

	var shells: Array = geo["shells"]
	for i in range(shells.size()):
		t += "[node name=\"Shell%d\" type=\"CollisionPolygon2D\" parent=\"EscapeDetector\"]\n" % i
		t += "polygon = %s\n\n" % _pv(shells[i])

	var f := FileAccess.open(Config.SCENE_RING, FileAccess.WRITE)
	if f == null:
		push_error("写不了 " + Config.SCENE_RING)
		quit(1)
		return
	f.store_string(t)
	f.close()
	print("WROTE ", Config.SCENE_RING, "  chars=", t.length(),
			"  arcs=", sectors.size(), " shells=", shells.size())
	quit()


func _pv(a: PackedVector2Array) -> String:
	var parts := PackedStringArray()
	for v in a:
		parts.append(_f(v.x))
		parts.append(_f(v.y))
	return "PackedVector2Array(%s)" % ", ".join(parts)


func _f(v: float) -> String:
	# 场景里的多边形只是编辑器预览，4 位小数足够；运行时会被精确值覆盖。
	if absf(v) < 0.00005:
		return "0"
	return String.num(v, 4)
