extends Node2D
## 结算庆祝效果：通关（逃出最后一个环）后播放。
##
## 组成
##   ConfettiStar / ConfettiSquare  GPUParticles2D  彩屑（官方粒子节点 + 程序化生成的贴图）
##   RingBurst                      GPUParticles2D  落点处的金色迸发
##   Anim                           AnimationPlayer 官方补间动画（标题弹出 + 撒花 + 淡出）
##   Ui/WinLabel                    Label           结算文字
##
## 所有可调参数（时长、淡出起点、文字颜色、弹出曲线、粒子数）集中在
## `scripts/config.gd` 的 `Config.CELEBRATION_*`。
##
## 动画用 AnimationPlayer 在代码里构建（而不是 .tscn 内联 Animation 资源），
## 这样关键帧在脚本里可读可调；如果用编辑器打开本场景，也会在 Anim 里看到它。
##
## 淡出经 modulate 实现：Label 在 Ui(CanvasLayer) 下不受本节点 modulate 影响，
## 所以本节点只淡出彩屑，Label 由动画里的 "Ui:modulate" 轨道单独淡出。

## 庆祝动画播完时发出。main 监听它来决定何时开下一局。
signal finished

var _fx_emitters: Array[GPUParticles2D] = []
var _win_label: Label


func _ready() -> void:
	_fx_emitters = [$ConfettiStar, $ConfettiSquare, $RingBurst]
	_win_label = $Ui/WinLabel
	# SystemFont 在 Godot 4 里没有 font_size 属性，字号走 theme override
	var f := SystemFont.new()
	f.font_names = PackedStringArray([Config.CELEBRATION_FONT_NAME])
	f.font_weight = Config.CELEBRATION_FONT_WEIGHT
	_win_label.add_theme_font_override("font", f)
	_win_label.add_theme_color_override("font_color", Config.CELEBRATION_TITLE_COLOR)
	_layout_win_label()
	# 固定 GPU 粒子随机种子，让彩屑图案逐帧可复现（见 Config.PARTICLE_FIXED_SEED）。
	# 三个发射器错开种子，免得星形与方形彩屑图案完全一致。
	var i := 0
	for p in _fx_emitters:
		p.use_fixed_seed = true
		p.seed = Config.PARTICLE_FIXED_SEED + 100 + i
		i += 1
	# 彩屑数量也从 Config 来；`celebration.tscn` 里的 amount 只是编辑器预览值。
	set_amounts(
			Config.CELEBRATION_STAR_AMOUNT,
			Config.CELEBRATION_SQUARE_AMOUNT,
			Config.CELEBRATION_BURST_AMOUNT)
	_build_animation()
	_set_hidden()


## 结算文字的位置与字号。
##
## 竖屏下盘面撑满宽度后，上下各会空出约 1/4 高度 —— "ESCAPED!" 就放在**下留白**：
## 既不会压住环，又正好接住往下落的彩屑（粒子 `gravity` 是向下的）。
## 位置用**锚点比例**表示（`Config.LAYOUT_CELEBRATION_Y`），所以换成更高分辨率
## 依然成立；字号从 `Config.CELEBRATION_FONT_SIZE` 来，`.tscn` 里的是编辑器预览值。
func _layout_win_label() -> void:
	var fs := float(Config.CELEBRATION_FONT_SIZE)
	_win_label.add_theme_font_size_override("font_size", Config.CELEBRATION_FONT_SIZE)
	_win_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_win_label.anchor_top = Config.LAYOUT_CELEBRATION_Y
	_win_label.anchor_bottom = Config.LAYOUT_CELEBRATION_Y
	_win_label.offset_left = 0.0
	_win_label.offset_right = 0.0
	_win_label.offset_top = 0.0
	_win_label.offset_bottom = fs * 1.4
	_win_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_win_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


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
	a.length = Config.CELEBRATION_TOTAL

	# 标题：从略小弹出到 1.0。
	# 注意 Animation.InterpolationType 只有 NEAREST/LINEAR/CUBIC（已查离线文档），
	# 没有 BACK —— 回弹效果靠 track_set_key_transition() 的负值缓动实现
	# （对应 @GlobalScope.ease()，<-1 会过冲）。
	var t := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(t, ^"Ui/WinLabel:scale")
	a.track_insert_key(t, 0.0, Config.CELEBRATION_POP_FROM)
	a.track_insert_key(t, Config.CELEBRATION_POP_TIME, Vector2.ONE)
	a.track_set_interpolation_type(t, Animation.INTERPOLATION_LINEAR)
	a.track_set_key_transition(t, 1, Config.CELEBRATION_POP_TRANSITION)

	var ta := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(ta, ^"Ui/WinLabel:modulate:a")
	a.track_insert_key(ta, 0.0, 0.0)
	a.track_insert_key(ta, Config.CELEBRATION_TITLE_FADE_IN, 1.0)
	a.track_insert_key(ta, Config.CELEBRATION_FADE_START, 1.0)
	a.track_insert_key(ta, Config.CELEBRATION_TOTAL, 0.0)

	# 彩屑整体淡出（Label 在 CanvasLayer 下，需单独处理，见上面那条轨道）
	var tm := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(tm, ^":modulate:a")
	a.track_insert_key(tm, 0.0, 1.0)
	a.track_insert_key(tm, Config.CELEBRATION_FADE_START, 1.0)
	a.track_insert_key(tm, Config.CELEBRATION_TOTAL, 0.0)

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


## 覆盖三个彩屑发射器的粒子数（`_ready()` 会先用 `Config.CELEBRATION_AMOUNTS`
## 调一次；想在别处临时改数量也可以再调）。
func set_amounts(star: int, square: int, ring: int) -> void:
	($ConfettiStar as GPUParticles2D).amount = maxi(1, star)
	($ConfettiSquare as GPUParticles2D).amount = maxi(1, square)
	($RingBurst as GPUParticles2D).amount = maxi(1, ring)


func _burst() -> void:
	for p in _fx_emitters:
		# ⚠️ `restart(true)` 保留种子；默认的 `restart()` 会重新抽种子，
		#    那样每次通关的彩屑图案都不同，成片就没法逐帧复现。
		p.restart(true)


func finish_now() -> void:
	$Anim.stop()
	_set_hidden()


func _on_anim_animation_finished(_name: StringName) -> void:
	_set_hidden()
	# 由 main 监听这个信号来决定何时开下一局，而不是在本脚本里直接切换场景状态
	finished.emit()
