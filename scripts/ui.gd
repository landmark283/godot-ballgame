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

## 玩家点了「应用并重开」。
signal apply_and_restart(cfg: Dictionary)
## 玩家点了「退出」回主菜单。
signal exit_to_menu
## 玩家点了「开始游戏」。
signal start_game

const PALETTES := {
	"Neon": [Color8(0, 255, 255), Color8(0, 150, 255), Color8(150, 50, 255), Color8(255, 0, 255), Color8(0, 255, 100)],
	"Fire": [Color8(255, 50, 0), Color8(255, 120, 0), Color8(255, 200, 50), Color8(200, 0, 0)],
	"Cyber": [Color8(255, 0, 150), Color8(100, 0, 255), Color8(0, 255, 200), Color8(50, 0, 150)],
	"Ocean": [Color8(0, 50, 200), Color8(0, 150, 255), Color8(100, 200, 255), Color8(0, 255, 180)],
	"Forest": [Color8(50, 255, 50), Color8(0, 150, 50), Color8(150, 255, 100)],
	"Pastel": [Color8(255, 180, 180), Color8(180, 255, 180), Color8(180, 180, 255)],
}

const BASE_COLORS := {
	"Cyan": Color8(0, 255, 255), "Red": Color8(255, 50, 50), "Green": Color8(50, 255, 50),
	"Gold": Color8(255, 215, 0), "Pink": Color8(255, 100, 255), "White": Color8(255, 255, 255),
	"Orange": Color8(255, 140, 0), "Purple": Color8(150, 0, 255), "Lime": Color8(180, 255, 0),
	"Blue": Color8(0, 100, 255), "Mint": Color8(170, 255, 195), "Crimson": Color8(220, 20, 60),
}

const MODES := ["Random", "Palette", "Custom"]
## 侧栏宽度（屏幕像素），与 pygame 原版一致。
const SIDEBAR_W := 300
## 数值参数的范围与步进。改这里即可，滑块与标签会自动跟上。
const SLIDERS := {
	"rings_count": {"label": "Rings", "min": 1.0, "max": 15.0, "step": 1.0, "fmt": "%d", "suffix": ""},
	"gravity": {"label": "Gravity", "min": 0.05, "max": 0.8, "step": 0.05, "fmt": "%.2f", "suffix": ""},
	"gap_size": {"label": "Gap Size", "min": 20.0, "max": 150.0, "step": 5.0, "fmt": "%d", "suffix": "°"},
}

var cfg := {
	"rings_count": 8, "rotation_speed": 1.8, "gap_size": 55, "gravity": 0.2,
	"ring_mode": "Random", "ring_val": "Neon", "ball_mode": "Random", "ball_val": "Gold",
}

var _menu: Control
var _sidebar: Control
var _hud: Control
var _wins_label: Label
var _value_labels := {}
var _sliders := {}
var _mode_buttons := {}
var _swatch_grids := {}
var _swatch_rows := {}
var _accent := Color8(0, 255, 180)


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
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", _accent)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var start := _make_button("START GAME", Color8(0, 150, 100))
	start.custom_minimum_size = Vector2(240, 60)
	start.add_theme_font_size_override("font_size", 18)
	start.pressed.connect(func() -> void: start_game.emit())
	box.add_child(start)


# --------------------------------------------------------------------- 侧栏

func _build_sidebar() -> void:
	_sidebar = Panel.new()
	_sidebar.anchor_left = 1.0
	_sidebar.anchor_right = 1.0
	_sidebar.anchor_top = 0.0
	_sidebar.anchor_bottom = 1.0
	_sidebar.offset_left = -float(SIDEBAR_W)
	_sidebar.offset_right = 0.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color8(20, 20, 25)
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
	head.add_theme_font_size_override("font_size", 18)
	head.add_theme_color_override("font_color", _accent)
	root.add_child(head)

	for key in SLIDERS.keys():
		_add_slider(root, key)

	_add_color_section(root, "ring")
	_add_color_section(root, "ball")

	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(filler)

	var apply_next := _make_button("APPLY (NEXT ROUND)", Color8(60, 60, 100))
	apply_next.tooltip_text = "与原作一致：本按钮不生效"
	apply_next.pressed.connect(func() -> void: pass)
	root.add_child(apply_next)

	var restart := _make_button("APPLY & RESTART", Color8(0, 120, 80))
	restart.pressed.connect(func() -> void: apply_and_restart.emit(cfg.duplicate()))
	root.add_child(restart)

	var ex := _make_button("EXIT", Color8(100, 50, 50))
	ex.pressed.connect(func() -> void: exit_to_menu.emit())
	root.add_child(ex)

	_build_hud()


## 独立于侧栏的 HUD：胜负计数与 UI 开关。侧栏收起时它必须还在，
## 否则玩家没法再把面板打开（`CanvasLayer` 不继承父节点 visible，
## 所以这里用独立分支而不是挂在侧栏里）。
func _build_hud() -> void:
	_hud = VBoxContainer.new()
	_hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_hud.position = Vector2(12, 10)
	_hud.add_theme_constant_override("separation", 4)
	add_child(_hud)

	_wins_label = Label.new()
	_wins_label.add_theme_font_size_override("font_size", 16)
	_hud.add_child(_wins_label)

	var toggle := _make_button("UI (H)", Color8(60, 60, 75))
	toggle.custom_minimum_size = Vector2(70, 24)
	toggle.pressed.connect(toggle_ui)
	_hud.add_child(toggle)


## 一行「标签 + 官方 HSlider + 当前值」
func _add_slider(parent: Node, key: String) -> void:
	var spec: Dictionary = SLIDERS[key]

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)

	var name_label := Label.new()
	name_label.text = String(spec["label"])
	name_label.add_theme_font_size_override("font_size", 12)
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
	value_label.add_theme_font_size_override("font_size", 12)
	value_label.custom_minimum_size = Vector2(34, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	_value_labels[key] = value_label


func _on_slider_changed(v: float, key: String) -> void:
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
	head.add_theme_font_size_override("font_size", 12)
	head.add_theme_color_override("font_color", Color8(150, 150, 150))
	parent.add_child(head)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)
	_mode_buttons[prefix] = {}
	for m in MODES:
		var b := _make_button(m)
		b.custom_minimum_size = Vector2(84, 22)
		b.add_theme_font_size_override("font_size", 11)
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
	for n in PALETTES.keys():
		items.append(n)
	for n in BASE_COLORS.keys():
		items.append(n)
	for n in items:
		var b := _make_button(String(n))
		b.custom_minimum_size = Vector2(62, 22)
		b.add_theme_font_size_override("font_size", 10)
		b.pressed.connect(_on_swatch_pressed.bind(prefix, String(n)))
		grid.add_child(b)
		_swatch_rows[prefix][String(n)] = b


func _on_mode_pressed(prefix: String, mode: String) -> void:
	cfg["%s_mode" % prefix] = mode
	_refresh()


func _on_swatch_pressed(prefix: String, name: String) -> void:
	cfg["%s_val" % prefix] = name
	_refresh()


func _make_button(text: String, bg: Color = Color8(60, 60, 75)) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 12)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color8(30, 30, 40)
	normal.border_color = bg
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(4)
	b.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.border_color = Color8(120, 120, 140)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	return b


# --------------------------------------------------------------------- 状态刷新

## 把 `cfg` 的当前值反映到控件上（数值文本、滑块位置、选中高亮、色板可见性）。
## 用 `set_value_no_signal` 写滑块，避免与 `value_changed` 形成回环。
func _refresh() -> void:
	for key in _value_labels.keys():
		var spec: Dictionary = SLIDERS[key]
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
			b.visible = PALETTES.has(n) == want_palette
			_mark(b, n == chosen)


func _mark(b: Button, active: bool) -> void:
	var sb := b.get_theme_stylebox("normal") as StyleBoxFlat
	if sb != null:
		sb.border_color = _accent if active else Color8(60, 60, 75)
		sb.set_border_width_all(2 if active else 1)


func set_menu_visible(menu_on: bool) -> void:
	_menu.visible = menu_on
	_sidebar.visible = not menu_on
	_hud.visible = not menu_on


func set_wins(n: int) -> void:
	if _wins_label != null:
		_wins_label.text = "Wins: %d" % n


func toggle_ui() -> void:
	_sidebar.visible = not _sidebar.visible


func sidebar_visible() -> bool:
	return _sidebar.visible
