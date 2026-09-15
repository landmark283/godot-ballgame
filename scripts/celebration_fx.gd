extends Node2D
## 结算庆祝效果：通关（逃出最后一个环）后播放。
##
## 组成
##   ConfettiStar / ConfettiSquare  GPUParticles2D  彩屑（官方粒子节点 + 程序化生成的贴图）
##   RingBurst                      GPUParticles2D  落点处的金色迸发
##   Anim                           AnimationPlayer 官方补间动画（标题弹出 + 撒花 + 淡出）
##   Ui/WinLabel                    Label           结算文字
##
## 动画用 AnimationPlayer 在代码里构建（而不是 .tscn 内联 Animation 资源），
## 这样关键帧在脚本里可读可调；如果用编辑器打开本场景，也会在 Anim 里看到它。
##
## 淡出经 modulate 实现：Label 在 Ui(CanvasLayer) 下不受本节点 modulate 影响，
## 所以本节点只淡出彩屑，Label 由动画里的 "Ui:modulate" 轨道单独淡出。

const TITLE_COLOR := Color(0, 1, 0.7, 1)
const FADE_START := 1.7
const TOTAL := 2.2

## 庆祝动画播完时发出。main 监听它来决定何时开下一局。
signal finished

var _fx_emitters: Array[GPUParticles2D] = []
var _win_label: Label


func _ready() -> void:
	_fx_emitters = [$ConfettiStar, $ConfettiSquare, $RingBurst]
	_win_label = $Ui/WinLabel
	# SystemFont 在 Godot 4 里没有 font_size 属性，字号走 theme override
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Arial"])
	f.font_weight = 900
	_win_label.add_theme_font_override("font", f)
	_win_label.add_theme_color_override("font_color", TITLE_COLOR)
	_build_animation()
	_set_hidden()


## ⚠️ CanvasLayer 不继承父 Node2D 的 visible，所以必须单独关掉 Ui，
## 否则 "ESCAPED!" 会在菜单页就一直显示着。一次性发射器也要显式停掉，
## 避免它们在场景原点自行发射。
func _set_hidden() -> void:
	visible = false
	$Ui.visible = false
	for p in _fx_emitters:
		p.emitting = false


func _build_animation() -> void:
	var a := Animation.new()
	a.length = TOTAL

	# 标题：从略小弹出到 1.0。
	# 注意 Animation.InterpolationType 只有 NEAREST/LINEAR/CUBIC（已查离线文档），
	# 没有 BACK —— 回弹效果靠 track_set_key_transition() 的负值缓动实现
	# （对应 @GlobalScope.ease()，<-1 会过冲）。
	var t := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(t, ^"Ui/WinLabel:scale")
	a.track_insert_key(t, 0.0, Vector2(0.4, 0.4))
	a.track_insert_key(t, 0.45, Vector2(1.0, 1.0))
	a.track_set_interpolation_type(t, Animation.INTERPOLATION_LINEAR)
	a.track_set_key_transition(t, 1, -2.2)

	var ta := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(ta, ^"Ui/WinLabel:modulate:a")
	a.track_insert_key(ta, 0.0, 0.0)
	a.track_insert_key(ta, 0.18, 1.0)
	a.track_insert_key(ta, FADE_START, 1.0)
	a.track_insert_key(ta, TOTAL, 0.0)

	# 彩屑整体淡出（Label 在 CanvasLayer 下，需单独处理，见上面那条轨道）
	var tm := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(tm, ^":modulate:a")
	a.track_insert_key(tm, 0.0, 1.0)
	a.track_insert_key(tm, FADE_START, 1.0)
	a.track_insert_key(tm, TOTAL, 0.0)

	# 用官方动画的 Call Method 轨道触发粒子（一次性发射器必须 restart()）。
	# ⚠️ 自节点的路径必须写 `"."`，写成 `":"` 归一化后是空路径，
	#    AnimationMixer 会无法解析并每帧刷
	#    `WARNING: AnimationMixer ... couldn't resolve track: ''`。
	var tc := a.add_track(Animation.TYPE_METHOD)
	a.track_set_path(tc, ^".")
	a.track_insert_key(tc, 0.0, {"method": &"_burst", "args": []})

	# Godot 4 里 AnimationPlayer 不再有 add_animation()，动画装进
	# AnimationLibrary 再挂到播放器上（已查离线文档确认）。
	var lib := AnimationLibrary.new()
	lib.add_animation("celebrate", a)
	$Anim.add_animation_library("", lib)
	$Anim.animation_finished.connect(_on_anim_animation_finished)


## 把结算效果放到指定的**世界坐标**并播放。
##
## 注意：本节点挂在 Camera2D 所管辖的世界里，4 个粒子发射器都设了
## `local_coords = false`，所以粒子的位置必须在世界坐标下给出 —— 相机负责
## 把它换算到屏幕。此前是手写 world_to_screen() 把屏幕坐标写进 position，
## 接入官方相机后那种算法会二次偏移。
func play_at(world_pos: Vector2) -> void:
	position = world_pos
	visible = true
	$Ui.visible = true
	_burst()
	$Anim.play("celebrate")


## 外部（如粒子配置）可在播放前调用，用来覆盖彩屑数量。
func set_amounts(star: int, square: int, ring: int) -> void:
	($ConfettiStar as GPUParticles2D).amount = maxi(1, star)
	($ConfettiSquare as GPUParticles2D).amount = maxi(1, square)
	($RingBurst as GPUParticles2D).amount = maxi(1, ring)


func _burst() -> void:
	for p in _fx_emitters:
		p.restart()


func finish_now() -> void:
	$Anim.stop()
	_set_hidden()


func _on_anim_animation_finished(_name: StringName) -> void:
	_set_hidden()
	# 由 main 监听这个信号来决定何时开下一局，而不是在本脚本里直接切换场景状态
	finished.emit()
