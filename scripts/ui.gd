extends CanvasLayer
## 界面：全部由 Godot 官方 `Control` 系节点组成
## （`Panel` / `VBoxContainer` / `HBoxContainer` / `GridContainer` / `Button` /
##  `HSlider` / `Label`）。
##
## 这里替换掉了原先手写的立即模式 `ui_btn()`：那种写法每帧在 `_draw()` 里画矩形、
## 自己算 hover 与点击命中区，等于自己重做了一遍 Godot 的控件系统，既拿不到
## 焦点/键盘导航/无障碍，也没法在编辑器里预览与调整。
##
## 数值参数用官方 `HSlider`（`HSlider < Slider < Range < Control`）而不是
## 自己写的"−/+"按钮：滑块天生带范围钳制、步进、键盘方向键操作与拖拽。
##
## 节点之间的沟通全部走信号：本节点只负责「把玩家的选择变成配置值并发出去」，
## 不直接去改游戏状态（那是 main 的职责）。
##
## 所有可调参数（配色、字号、滑块范围、默认配置）集中在 `scripts/config.gd`；
## 本文件里的数字只剩**布局尺寸**（控件间距、最小宽高）——那些就地读更清楚。

## 玩家点了「应用并重开」。
signal apply_and_restart(cfg: Dictionary)
## 玩家点了「退出」回主菜单。
signal exit_to_menu
## 玩家点了「开始游戏」。
signal start_game
## 玩家点了任意按钮 —— main 接到后播音效。
## 用信号而不是让 UI 自己持有播放器：音频归 `AudioFX` 管，UI 只管发事件
## （与 `ball.bounced` / `ring.escaped` 同一套做法）。
signal ui_click

## 当前配置。默认值来自 `Config.DEFAULT_CFG`（与 main 共用同一份，不再各写一份）。
var cfg := Config.DEFAULT_CFG.duplicate()

var _menu: Control
var _sidebar: Control
var _hud: Control
var _wins_label: Label
## 成片版式：顶部游戏名。竖屏留白处，**属于视频画面的一部分**。
var _title_label: Label
## 右上角的「UI (H)」按钮 —— 制作工具，不进成片。
var _toggle: Button
var _value_labels := {}
var _sliders := {}
var _mode_buttons := {}
var _swatch_grids := {}
var _swatch_rows := {}
var _accent := Config.UI_ACCENT


func _ready() -> void:
	_build_menu()
	_build_sidebar()
	_refresh()
	set_menu_visible(true)


# --------------------------------------------------------------------- 主菜单

func _build_menu() -> void:
	_menu = Control.new()
	_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_menu)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 28)
	_menu.add_child(box)

	var title := Label.new()
	title.text = "BALL ESCAPE: KINETIC"
	title.add_theme_font_size_override("font_size", Config.FONT_TITLE)
	title.add_theme_color_override("font_color", _accent)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var start := _make_button("START GAME", Config.UI_BUTTON_START)
	start.custom_minimum_size = Vector2(240, 60)
	start.add_theme_font_size_override("font_size", Config.FONT_BUTTON_LARGE)
	start.pressed.connect(func() -> void:
		ui_click.emit()
		start_game.emit())
	box.add_child(start)


# --------------------------------------------------------------------- 侧栏

func _build_sidebar() -> void:
	_sidebar = Panel.new()
	_sidebar.anchor_left = 1.0
	_sidebar.anchor_right = 1.0
	_sidebar.anchor_top = 0.0
	_sidebar.anchor_bottom = 1.0
	_sidebar.offset_left = -Config.SIDEBAR_WIDTH
	_sidebar.offset_right = 0.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Config.UI_PANEL_BG
	_sidebar.add_theme_stylebox_override("panel", sb)
	add_child(_sidebar)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 16
	root.offset_right = -16
	root.offset_top = 16
	root.offset_bottom = -16
	root.add_theme_constant_override("separation", 12)
	_sidebar.add_child(root)

	var head := Label.new()
	head.text = "PHYSICS & GAP"
	head.add_theme_font_size_override("font_size", Config.FONT_HEADING)
	head.add_theme_color_override("font_color", _accent)
	root.add_child(head)

	for key in Config.SLIDERS.keys():
		_add_slider(root, key)

	_add_color_section(root, "ring")
	_add_color_section(root, "ball")

	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(filler)

	var apply_next := _make_button("APPLY (NEXT ROUND)", Config.UI_BUTTON_APPLY_NEXT)
	apply_next.tooltip_text = "与原作一致：本按钮不生效"
	apply_next.pressed.connect(func() -> void: pass)
	root.add_child(apply_next)

	var restart := _make_button("APPLY & RESTART", Config.UI_BUTTON_RESTART)
	restart.pressed.connect(func() -> void:
		ui_click.emit()
		apply_and_restart.emit(cfg.duplicate()))
	root.add_child(restart)

	var ex := _make_button("EXIT", Config.UI_BUTTON_EXIT)
	ex.pressed.connect(func() -> void:
		ui_click.emit()
		exit_to_menu.emit())
	root.add_child(ex)

	_build_hud()


## 竖屏版式：盘面是圆的，撑满宽度后上下各空出约 1/4 高度 —— 那里就是放字的地方。
## 顶部放**游戏名 + HUD**，底部留给结算文字（见 `celebration_fx.gd::_layout_win_label()`）。
##
## 竖直位置用**占视口高度的比例**（`Config.LAYOUT_*_Y`）而不是像素，
## 所以换成 1440×2560 等更高分辨率依然成立。
##
## ⚠️ 这些是**成片的一部分**，不像侧栏那样默认藏起来 —— 别把它们塞进
##    `set_chrome_visible()` 里。侧栏收起时它们也必须还在（`CanvasLayer`
##    不继承父节点 visible，所以这里是独立分支而不是挂在侧栏内）。
func _build_hud() -> void:
	_title_label = Label.new()
	_title_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_title_label.anchor_top = Config.LAYOUT_TITLE_Y
	_title_label.anchor_bottom = Config.LAYOUT_TITLE_Y
	_title_label.offset_bottom = float(Config.FONT_TITLE) * 1.3
	_title_label.text = "BALL ESCAPE"
	_title_label.add_theme_font_size_override("font_size", Config.FONT_TITLE)
	_title_label.add_theme_color_override("font_color", _accent)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_title_label)

	_hud = VBoxContainer.new()
	_hud.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_hud.anchor_top = Config.LAYOUT_HUD_Y
	_hud.anchor_bottom = Config.LAYOUT_HUD_Y
	_hud.offset_bottom = float(Config.FONT_HUD) * 1.6
	add_child(_hud)

	_wins_label = Label.new()
	_wins_label.add_theme_font_size_override("font_size", Config.FONT_HUD)
	_wins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.add_child(_wins_label)

	# 工具按钮浮在右上角，用 H 键或它来收放侧栏；录制时会被隐藏。
	_toggle = _make_button("UI (H)", Config.UI_BUTTON_TOGGLE)
	_toggle.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_toggle.custom_minimum_size = Vector2(120, 52)
	_toggle.offset_left = -132.0
	_toggle.offset_right = -12.0
	_toggle.offset_top = 12.0
	_toggle.offset_bottom = 64.0
	_toggle.pressed.connect(toggle_ui)
	add_child(_toggle)


## `H` 键收放配置侧栏。按钮上写着 "UI (H)"，之前却**没有任何键盘处理** ——
## 侧栏一藏就只能靠那个按钮，按钮再被隐藏就彻底打不开了。
func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and k.keycode == KEY_H:
		toggle_ui()
		get_viewport().set_input_as_handled()


## 一行「标签 + 官方 HSlider + 当前值」。
## 范围/步进/标签/格式全部来自 `Config.SLIDERS`，改那里即可。
func _add_slider(parent: Node, key: String) -> void:
	var spec: Dictionary = Config.SLIDERS[key]

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)

	var name_label := Label.new()
	name_label.text = String(spec["label"])
	name_label.add_theme_font_size_override("font_size", Config.FONT_LABEL)
	name_label.custom_minimum_size = Vector2(64, 0)
	row.add_child(name_label)

	var slider := HSlider.new()
	slider.min_value = float(spec["min"])
	slider.max_value = float(spec["max"])
	slider.step = float(spec["step"])
	slider.custom_minimum_size = Vector2(120, 20)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 官方 Range 的 value_changed(value: float) 信号，拖拽时连续触发。
	# 用 bind 把 key 传给同一个处理函数，避免在循环里写多个 lambda。
	slider.value_changed.connect(_on_slider_changed.bind(key))
	row.add_child(slider)
	_sliders[key] = slider

	var value_label := Label.new()
	value_label.add_theme_font_size_override("font_size", Config.FONT_LABEL)
	value_label.custom_minimum_size = Vector2(34, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	_value_labels[key] = value_label


func _on_slider_changed(v: float, key: String) -> void:
	# ⚠️ 拖滑块时 value_changed 会每帧连发，**不能**在这里 emit ui_click ——
	#    那会变成一秒钟几十下点击音糊成噪音。只播按钮类的离散点击。
	# rings_count 是整数参数（Slider 的 value 是 float）
	if key == "rings_count":
		cfg[key] = int(round(v))
	else:
		cfg[key] = snappedf(v, 0.001)
	_refresh()


func _add_color_section(parent: Node, prefix: String) -> void:
	var m_key := "%s_mode" % prefix
	var v_key := "%s_val" % prefix

	var head := Label.new()
	head.text = "%s COLOR" % prefix.to_upper()
	head.add_theme_font_size_override("font_size", Config.FONT_LABEL)
	head.add_theme_color_override("font_color", Config.UI_MUTED_TEXT)
	parent.add_child(head)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)
	_mode_buttons[prefix] = {}
	for m in Config.COLOR_MODES:
		var b := _make_button(m)
		b.custom_minimum_size = Vector2(84, 22)
		b.add_theme_font_size_override("font_size", Config.FONT_SMALL)
		b.pressed.connect(_on_mode_pressed.bind(prefix, m))
		row.add_child(b)
		_mode_buttons[prefix][m] = b

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	parent.add_child(grid)
	_swatch_grids[prefix] = grid
	_swatch_rows[prefix] = {}

	var items: Array = []
	for n in Config.PALETTES.keys():
		items.append(n)
	for n in Config.BASE_COLORS.keys():
		items.append(n)
	for n in items:
		var b := _make_button(String(n))
		b.custom_minimum_size = Vector2(62, 22)
		b.add_theme_font_size_override("font_size", Config.FONT_TINY)
		b.pressed.connect(_on_swatch_pressed.bind(prefix, String(n)))
		grid.add_child(b)
		_swatch_rows[prefix][String(n)] = b


func _on_mode_pressed(prefix: String, mode: String) -> void:
	ui_click.emit()
	cfg["%s_mode" % prefix] = mode
	_refresh()


func _on_swatch_pressed(prefix: String, name: String) -> void:
	ui_click.emit()
	cfg["%s_val" % prefix] = name
	_refresh()


func _make_button(text: String, bg: Color = Config.UI_BUTTON_BORDER) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", Config.FONT_BUTTON)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Config.UI_BUTTON_BG
	normal.border_color = bg
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(4)
	b.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.border_color = Config.UI_BUTTON_BORDER_HOVER
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	return b


# --------------------------------------------------------------------- 状态刷新

## 把 `cfg` 的当前值反映到控件上（数值文本、滑块位置、选中高亮、色板可见性）。
## 用 `set_value_no_signal` 写滑块，避免与 `value_changed` 形成回环。
func _refresh() -> void:
	for key in _value_labels.keys():
		var spec: Dictionary = Config.SLIDERS[key]
		var v: float = float(cfg[key])
		_value_labels[key].text = (String(spec["fmt"]) % (int(round(v)) if String(spec["fmt"]) == "%d" else v)) + String(spec["suffix"])
		var slider: HSlider = _sliders[key]
		if not is_equal_approx(slider.value, v):
			slider.set_value_no_signal(v)
	for prefix in _mode_buttons.keys():
		var m: String = cfg["%s_mode" % prefix]
		for mode in _mode_buttons[prefix].keys():
			_mark(_mode_buttons[prefix][mode], mode == m)
		var want_palette: bool = m == "Palette"
		_swatch_grids[prefix].visible = m != "Random"
		var chosen: String = cfg["%s_val" % prefix]
		for n in _swatch_rows[prefix].keys():
			var b: Button = _swatch_rows[prefix][n]
			b.visible = Config.PALETTES.has(n) == want_palette
			_mark(b, n == chosen)


func _mark(b: Button, active: bool) -> void:
	var sb := b.get_theme_stylebox("normal") as StyleBoxFlat
	if sb != null:
		sb.border_color = _accent if active else Config.UI_BUTTON_BORDER
		sb.set_border_width_all(2 if active else 1)


func set_menu_visible(menu_on: bool) -> void:
	_menu.visible = menu_on
	# 进游戏后侧栏**默认收起**：竖屏下盘面撑满宽度，300px 的侧栏会盖住环。
	# 需要调参时按 H 或点右上角按钮（那时相机会自动把盘面缩小让位）。
	_sidebar.visible = false
	_title_label.visible = not menu_on
	_hud.visible = not menu_on
	_toggle.visible = not menu_on


func set_wins(n: int) -> void:
	if _wins_label != null:
		_wins_label.text = "Wins: %d" % n


func toggle_ui() -> void:
	_sidebar.visible = not _sidebar.visible


## 隐藏/显示**制作工具**（配置侧栏 + 右上角按钮）—— 成片里不该出现它们。
##
## ⚠️ 顶部标题与 HUD **不**在这里：竖屏上下留白就是用来放它们的，
##    它们是成片版式的一部分（见 `_build_hud()`）。
func set_chrome_visible(on: bool) -> void:
	_sidebar.visible = on
	_toggle.visible = on


func sidebar_visible() -> bool:
	return _sidebar.visible
