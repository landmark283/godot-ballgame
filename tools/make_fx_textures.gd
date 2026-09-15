extends SceneTree
## 一次性工具：生成庆祝效果用的粒子贴图。
##
## 为什么不直接下载现成素材：本机沙箱的 TLS 吊销检查失败
## （curl 报 CRYPT_E_REVOCATION_OFFLINE），连本地代理也连不通 GitHub，
## 外部素材下不下来。改用 Godot 自己的 Image API 程序化生成 ——
## 自持、离线可用、可进版本控制，而且不引入任何第三方授权问题。
##
## 运行方式（生成脚本放在项目内，--script 需要 SceneTree/MainLoop）：
##   Godot.exe --headless --path godot-ballgame --script res://tools/make_fx_textures.gd
##
## 会写出：
##   res://assets/fx/confetti_star.png   五角星
##   res://assets/fx/confetti_square.png 方片
##
## Image 没有 fill_polygon（已查离线文档确认），所以自己做
## 4× 超采样 + 多边形填色的光栅化，再降采样得到抗锯齿边缘。

const OUT_DIR := "res://assets/fx"
const SS := 4              # 超采样倍数
const STAR_R := 100.0      # 超采样坐标系下的外半径

var _poly: PackedVector2Array = []


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_save("confetti_star.png", _render_star())
	_save("confetti_square.png", _render_square())
	print("MAKEFX done")
	quit(0)


func _save(file_name: String, img: Image) -> void:
	var path := "%s/%s" % [OUT_DIR, file_name]
	var err := img.save_png(path)
	# 自检：统计不透明像素占比与包围盒，确认形状真的画出来了
	var opaque := 0
	var full := 0
	var minx := 9999
	var maxx := -1
	var miny := 9999
	var maxy := -1
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var a := img.get_pixel(x, y).a
			if a > 0.5:
				opaque += 1
				if x < minx: minx = x
				if x > maxx: maxx = x
				if y < miny: miny = y
				if y > maxy: maxy = y
			if a > 0.99:
				full += 1
	var total := img.get_width() * img.get_height()
	print("MAKEFX ", path, " err=", err, " opaque=", opaque, "/", total,
		" (", snappedf(opaque * 100.0 / total, 0.1), "%) full=", full,
		" bbox=[", minx, ",", miny, " .. ", maxx, ",", maxy, "]")


# --------------------------------------------------------------- 五角星

## 生成星形多边形（超采样坐标系，中心为原点）。
func _build_star_polygon() -> PackedVector2Array:
	var pts := PackedVector2Array()
	var inner_r := STAR_R * 0.42
	# 10 个顶点交替取外/内半径；从 -90° 起算使尖角朝上
	for i in range(10):
		var r := STAR_R if (i % 2 == 0) else inner_r
		var a := deg_to_rad(-90.0 + i * 36.0)
		pts.append(Vector2(cos(a), sin(a)) * r)
	return pts


func _render_star() -> Image:
	_poly = _build_star_polygon()
	return _rasterize()


func _render_square() -> Image:
	var s := STAR_R * 0.78
	_poly = PackedVector2Array([
		Vector2(-s, -s), Vector2(s, -s), Vector2(s, s), Vector2(-s, s),
	])
	return _rasterize()


## 4× 超采样光栅化后降采样，得到带抗锯齿的 64×64 白色遮罩贴图。
func _rasterize() -> Image:
	var hi := 64 * SS
	var bi := Image.create_empty(hi, hi, false, Image.FORMAT_RGBA8)
	var c := Vector2(hi * 0.5, hi * 0.5)
	for y in range(hi):
		for x in range(hi):
			if _point_in_poly(Vector2(x + 0.5, y + 0.5) - c, _poly):
				bi.set_pixel(x, y, Color(1, 1, 1, 1))
	var out := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	for y in range(64):
		for x in range(64):
			var acc := 0.0
			for dy in range(SS):
				for dx in range(SS):
					acc += bi.get_pixel(x * SS + dx, y * SS + dy).a
			out.set_pixel(x, y, Color(1, 1, 1, acc / float(SS * SS)))
	return out


## 射线法判断点是否在多边形内（顶点顺序无关）。
func _point_in_poly(p: Vector2, poly: PackedVector2Array) -> bool:
	var inside := false
	var n := poly.size()
	var j := n - 1
	for i in range(n):
		var a := poly[i]
		var b := poly[j]
		if ((a.y > p.y) != (b.y > p.y)):
			var x_at := (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x
			if p.x < x_at:
				inside = not inside
		j = i
	return inside
