class_name Config
## ============================================================================
##  全局配置 —— 所有可调参数都集中在本文件
## ============================================================================
##
## 调世界尺度、物理手感、环/球几何、配色、字号、滑块范围、粒子、庆祝动画，
## 都只改这一个文件，不必再翻别的脚本。
##
## ## 刻意**不**放在这里的参数（避免同一个值有两处定义）
##
## | 类别                                   | 去处                | 为什么                      |
## | -------------------------------------- | ------------------- | --------------------------- |
## | 视口尺寸 / 物理频率 / 渲染器 / 碰撞层名 | `project.godot`     | Godot 官方位置，引擎直接读  |
## | 颜色渐变、缩放曲线等观感                | 各自的 `.tscn`      | 需要在编辑器里可视化预览    |
## | 布局尺寸（控件间距、最小宽高）          | `ui.gd` 构建函数    | 就地可读，改了要连着看布局  |
##
## ## 取值优先级（高 → 低）
##
## ```
## particles.cfg（可选覆盖，只认它显式写出的键）
##   > 本文件的 PARTICLES
##     > 场景里保存的值
## ```
##
## `particles.cfg` 默认**全部注释掉**（等于不存在覆盖），所以出厂状态下
## 粒子参数的唯一来源就是本文件。
##
## ## ⚠️ 改 const 字典的注意事项
##
## Godot 4 里 `const` 的 `Dictionary` / `Array` 是**只读**的，运行时改它会报错。
## 需要一份可改的副本时先 `.duplicate()`（例如 `Config.DEFAULT_CFG.duplicate()`）。


# ============================================================================
#  世界 / 相机
# ============================================================================

## 盘面直径占**可见游戏区宽度**的比例。相机 zoom 由它反推 ——
## 所以换分辨率不会改变构图，想让盘面更大/更小也只改这一个数。
## 默认：竖屏 1080 宽、8 环（外沿 457 世界单位）→ zoom = 1080×0.92/914 ≈ 1.087。
##
## ⚠️ 这里**没有** `WORLD_SCALE` 了。旧版把「世界→屏幕」缩放**乘了两次**
##    （几何里 ×0.7，相机 zoom 再 ×0.7，净 0.49），结果盘面只占画面宽的 33%；
##    而且内容放在 `WORLD_CENTER × WORLD_SCALE`、相机却看 `WORLD_CENTER`，
##    盘面整体偏离中心 `(-105, -105)` px。现在缩放只由**相机**承担一份。
const PLAYFIELD_FILL := 0.92
## 环心所在的世界坐标（pygame 原版的 `V_CENTER`）。**也是相机看的位置** ——
## 内容与相机必须共用这一个数，否则盘面就会偏离画面中心（旧版正是这么坏的）。
const WORLD_CENTER := Vector2(500.0, 500.0)
## 侧栏宽度（屏幕像素）。侧栏展开时，相机把盘面摆到**剩余区域**正中并相应缩小，
## 所以展开侧栏不会盖住环。
const SIDEBAR_WIDTH := 300.0
## 「球已飞出可见范围」判定区 = 视口能容纳的世界范围 × 本系数。
## 太紧会在球还看得见时就判出界，太松则要等很久。
const PLAYFIELD_MARGIN := 1.6


# ============================================================================
#  竖屏版式（视口 1080×1920，见 `project.godot`）
# ============================================================================
#
# 盘面是圆的，竖屏下「撑满宽度」之后上下必然空出约 1/4 高度 —— 那里放文字。
# 竖直位置用**占视口高度的比例**表示，于是换到 1440×2560 等更高分辨率仍然成立。

## 顶部标题（游戏名）的竖直位置。
const LAYOUT_TITLE_Y := 0.072
## 顶部副信息（Wins / 剩余环数）的竖直位置。
const LAYOUT_HUD_Y := 0.145
## 底部结算文字（ESCAPED!）的竖直位置。彩屑受重力往下落，正好落在它周围。
const LAYOUT_CELEBRATION_Y := 0.855


# ============================================================================
#  场景路径
# ============================================================================

const SCENE_RING := "res://ring.tscn"
const SCENE_BALL := "res://ball.tscn"
const SCENE_UI := "res://ui.tscn"
const SCENE_AUDIO := "res://audio_fx.tscn"
## 粒子参数的**可选**覆盖文件。不存在、或存在但没写某个键，都回落到 `PARTICLES`。
const PARTICLES_OVERRIDE_PATH := "res://particles.cfg"
## 生成 `ring.tscn` 用的工具脚本（`godot --headless --script res://tools/...`）。
const TOOL_BUILD_RING_SCENE := "res://tools/build_ring_scene.gd"


# ============================================================================
#  圆环
# ============================================================================

## 第 0 个环的环心线世界半径，之后每个 +RING_RADIUS_STEP。
const RING_FIRST_WORLD_RADIUS := 100.0
const RING_RADIUS_STEP := 50.0
## 弧带厚度（世界单位）。
const RING_WORLD_THICKNESS := 14.0
## 缺口角宽度（度）的默认值；实际值由 `DEFAULT_CFG.gap_size` 决定。
const RING_GAP_DEG := 55.0

## 弧带的角度细分段数。显示、弧带碰撞、逃出探测环壳共用同一批角度，逐点一致。
const RING_ARC_SEGMENTS := 48
## 把弧带/环壳切成几个**简单**（非自交）扇段交给引擎凸分解。
## 实测：整条弧带作为**一个**多边形也能被正确分解，但切开后顶点更少、分解更稳；
## 自交多边形才是会静默分解失败的那种（见 README 第 5 条）。
const RING_ARC_CHUNKS := 4

## 每物理帧允许的**切向扫掠**上限，取环带半厚的一个比例。
##
## 为什么必须有上限：`SolidBody` 是 `StaticBody2D`，它的运动**没有**连续碰撞检测，
## 每个物理步是直接跳到新位置的（官方 troubleshooting：「让每个物理步的位移远小于
## 碰撞体尺寸」）。球自己用 `move_and_collide()` 扫掠，球速不是问题；出问题的是
## **环壁扫过来** —— 一步压进球的深度超过「球心到最近那条外弧的距离」时，接触的
## 最近面会从缺口的径向切面翻成外弧，解算于是沿外法线把球推出环外（球壁穿模）。
## 实测（半径 70px 的环）：扫掠 14.7px/帧 时 600 次对撞有 20 次穿模；
## ≤3.67px/帧 时 0 次。
##
## **副作用**：外圈环的角速度会低于 `DEFAULT_CFG.rotation_speed`（各环边缘线速度
## 趋于一致）。默认参数下内两圈不受影响，最外圈约降到 1/3。想让外圈转得更快就调大
## 本系数，代价是重新暴露上面的穿模。
const RING_MAX_SWEEP_HALF_THICKNESS := 0.75

## 逃出探测环壳的径向厚度（× 球半径）。
##
## 必须够厚：环壁扫到球时，解算会把球**一步弹出很远**（实测单步可达 ~35px）。
## 环壳若只有一两个球半径厚，这种跳变会整个跨过去 —— 球到了环外、环却没碎，
## 又回到「整局卡死」。
const RING_SHELL_RADIAL_BALL_RADII := 8.0
## 破环线 = 环心线 + 厚度 × 本系数（pygame 原版 `dist > r + thickness/3`）。
const RING_BREAK_BIAS := 1.0 / 3.0


# ============================================================================
#  小球
# ============================================================================

## 球半径（世界单位）。
const BALL_WORLD_RADIUS := 12.0
## 显示用圆的细分段数。
const BALL_CIRCLE_STEPS := 32
## 碰撞后保留的速度比例（pygame 原版为 0.98）。
const BALL_RESTITUTION := 0.98
## 「速度过小就加速」的阈值（世界单位 / 物理帧）。
##
## ⚠️ 必须与内部速度同尺度。原版直接拿**像素/帧**速度比较 1.0；本实现内部速度是
## **世界单位/物理帧**，若沿用 1.0 会让正常速度（≈3）每帧都低于阈值、每帧乘 1.1，
## 速度指数爆炸（实测 3000 帧后球距环心 18 万像素）。
const BALL_MIN_SPEED := 1.0
## 速度低于阈值时的放大倍数（pygame 原版 `* 1.1`）。
const BALL_MIN_SPEED_MULT := 1.1
## 开局初速（世界单位 / 物理帧）。x 分量随机取 ±BALL_LAUNCH_SPEED_X，
## y 分量在 ±BALL_LAUNCH_SPEED_Y 内均匀取值。
const BALL_LAUNCH_SPEED_X := 5.0
const BALL_LAUNCH_SPEED_Y := 3.0
## 重力默认值（世界单位 / 物理帧²）；实际由 `DEFAULT_CFG.gravity` 决定。
const BALL_GRAVITY := 0.02


# ============================================================================
#  默认玩法配置（UI 侧栏与 main 共用同一份，不要再各写一份）
# ============================================================================

const DEFAULT_CFG := {
	"rings_count": 8,
	"rotation_speed": 1.8,
	"gap_size": 55,
	"gravity": 0.2,
	"ring_mode": "Random",
	"ring_val": "Neon",
	"ball_mode": "Random",
	"ball_val": "Gold",
}


# ============================================================================
#  UI：配色
# ============================================================================

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

## 取色模式：随机 / 调色板 / 单色。
const COLOR_MODES := ["Random", "Palette", "Custom"]

## UI 用色。
const UI_ACCENT := Color8(0, 255, 180)
const UI_PANEL_BG := Color8(20, 20, 25)
const UI_BUTTON_BG := Color8(30, 30, 40)
const UI_BUTTON_BORDER := Color8(60, 60, 75)
const UI_BUTTON_BORDER_HOVER := Color8(120, 120, 140)
const UI_MUTED_TEXT := Color8(150, 150, 150)
## 各按钮的强调色（用作 normal 状态描边）。
const UI_BUTTON_START := Color8(0, 150, 100)
const UI_BUTTON_APPLY_NEXT := Color8(60, 60, 100)
const UI_BUTTON_RESTART := Color8(0, 120, 80)
const UI_BUTTON_EXIT := Color8(100, 50, 50)
const UI_BUTTON_TOGGLE := Color8(60, 60, 75)


# ============================================================================
#  UI：字号
# ============================================================================

const FONT_TITLE := 84          ## 主菜单大标题 / 顶部游戏名（竖屏留白处，要够大）
const FONT_HEADING := 26        ## 侧栏分区标题
const FONT_BUTTON_LARGE := 30   ## START GAME
const FONT_HUD := 44            ## Wins 计数（顶部留白处的副信息）
const FONT_BUTTON := 20         ## 常规按钮
const FONT_LABEL := 20          ## 滑块名称 / 数值
const FONT_SMALL := 18          ## 取色模式按钮
const FONT_TINY := 16           ## 色板按钮


# ============================================================================
#  UI：数值滑块（改这里，滑块与数值标签会自动跟上）
# ============================================================================

const SLIDERS := {
	"rings_count": {"label": "Rings", "min": 1.0, "max": 15.0, "step": 1.0, "fmt": "%d", "suffix": ""},
	"gravity": {"label": "Gravity", "min": 0.05, "max": 0.8, "step": 0.05, "fmt": "%.2f", "suffix": ""},
	"gap_size": {"label": "Gap Size", "min": 20.0, "max": 150.0, "step": 5.0, "fmt": "%d", "suffix": "°"},
}


# ============================================================================
#  粒子（GPUParticles2D + ParticleProcessMaterial）
# ============================================================================
##
## 这些是**数值**参数；颜色渐变、缩放曲线等观感项留在 `particle_fx.tscn` 里，
## 方便在编辑器中可视化调。
##
## 键名与 `particle_fx.gd::_apply()` 读取的一致；具体含义见下方注释。
## 想调更多官方参数（turbulence、sub_emitter、发射形状……）直接改那个场景。
##

## 粒子的固定随机种子。
##
## GPU 粒子的随机数是**引擎自己抽的**，默认每次运行都不同 —— 球撞得一模一样、
## 火花却每次都不一样，两次渲染的成片哈希自然对不上。官方为此提供了
## `GPUParticles2D.use_fixed_seed`，文档原话就是
## 「useful for situations where the visual outcome should be consistent across
## replays, for example when using Movie Maker mode」—— 正是本项目的场景。
##
## ⚠️ 光设 `use_fixed_seed` 还不够：`restart()` 默认会**重新抽种子**，
##    一次性发射器每次撞击都要 restart，所以必须调 `restart(true)` 保留种子。
##    两处都在 `particle_fx.gd` / `celebration_fx.gd` 里改好了。
const PARTICLE_FIXED_SEED := 20260214
## | 键                      | 含义                                       |
## | ----------------------- | ------------------------------------------ |
## | `one_shot`              | 一次性爆发（用完要 `restart()`）           |
## | `amount`                | 粒子数                                     |
## | `lifetime`              | 寿命（秒）。⚠️ 见 `scale` 的联动说明       |
## | `explosiveness`         | 0=均匀喷洒，1=全部同时喷出                 |
## | `spread`                | 张角（度）                                 |
## | `velocity_min/max`      | 初速（像素/秒）                            |
## | `damping_min/max`       | 阻尼（越大越快停下）                       |
## | `gravity`               | 下坠加速度                                 |
## | `scale_min/max`         | 粒子尺寸。屏上尺寸 ≈ `scale × lifetime`    |
## | `enabled`               | 持续型发射器是否默认开启                   |
## | `emission_radius`       | 发射球半径（像素）；不写则用场景值         |
## | `emission_radius_scale` | 发射球半径 = 球半径 × 本系数               |
## | `sample_interval`       | 每几帧发射一次（1=每帧，最密）             |

const PARTICLES := {
	# 球撞到圆环实心处的碰撞反馈（一次性，朝撞击点法线扇开）
	"burst": {
		"one_shot": true,
		"amount": 18,
		"lifetime": 0.35,
		"explosiveness": 1.0,
		"spread": 45.0,
		"velocity_min": 100.0,
		"velocity_max": 220.0,
		"damping_min": 20.0,
		"damping_max": 60.0,
		"gravity": 60.0,
		"scale_min": 1.6,
		"scale_max": 3.2,
	},
	# 球从缺口逃出、圆环碎裂（一次性，整圈铺开）
	"ring_break": {
		"one_shot": true,
		"amount": 18,
		"lifetime": 0.45,
		"explosiveness": 1.0,
		"spread": 180.0,
		"velocity_min": 60.0,
		"velocity_max": 260.0,
		"damping_min": 10.0,
		"damping_max": 40.0,
		"gravity": 40.0,
		"scale_min": 1.8,
		"scale_max": 4.0,
	},
	# 小球运动轨迹（官方 trail_enabled 拖尾）
	#
	# 参数按球的真实屏幕速度标定：球约 85px/s。实测（受控直线实验）：
	# amount=160/lifetime=1.2 时轨迹延伸约 106px。下列取值按比例收短到约 60px，
	# 与球半径（约 8px）的比例更协调。
	"trail": {
		"one_shot": false,
		"enabled": true,
		"amount": 120,
		"lifetime": 0.8,
		"spread": 18.0,
		"velocity_min": 20.0,
		"velocity_max": 80.0,
		"damping_min": 10.0,
		"damping_max": 30.0,
		"gravity": 0.0,
		# ⚠️ 屏上尺寸 ≈ scale_max × lifetime，所以改 lifetime 必须同步改 scale。
		# 0.9 × 0.8 ≈ 0.7px 粒子。
		"scale_min": 0.5,
		"scale_max": 0.9,
		"sample_interval": 1,
		"emission_radius_scale": 0.5,
	},
}


# ============================================================================
#  结算庆祝动画
# ============================================================================

## 整段动画时长（秒）。`main` 靠它结束后开下一局。
const CELEBRATION_TOTAL := 2.2
## 从这一时刻开始淡出。
const CELEBRATION_FADE_START := 1.7
## "ESCAPED!" 文字颜色。
const CELEBRATION_TITLE_COLOR := Color(0, 1, 0.7, 1)
## 标题弹出：从 POP_FROM 缩放到 1.0，用时 POP_TIME。
const CELEBRATION_POP_FROM := Vector2(0.4, 0.4)
const CELEBRATION_POP_TIME := 0.45
## 回弹缓动（对应 @GlobalScope.ease()；<-1 会过冲）。
## ⚠️ `Animation.InterpolationType` 只有 NEAREST/LINEAR/CUBIC，没有 BACK，
##    所以过冲只能靠 track_set_key_transition() 的负值实现。
const CELEBRATION_POP_TRANSITION := -2.2
## 标题淡入耗时。
const CELEBRATION_TITLE_FADE_IN := 0.18
## 三个彩屑发射器的粒子数。改这里即可（`celebration.tscn` 里的是编辑器预览值）。
const CELEBRATION_STAR_AMOUNT := 90
const CELEBRATION_SQUARE_AMOUNT := 70
const CELEBRATION_BURST_AMOUNT := 48
## 结算文字用的系统字体（`SystemFont` 没有 font_size 属性，字号走 theme override）。
const CELEBRATION_FONT_NAME := "Arial"
const CELEBRATION_FONT_WEIGHT := 900
## "ESCAPED!" 的字号。**由脚本写入**，`celebration.tscn` 里的是编辑器预览值。
const CELEBRATION_FONT_SIZE := 110


# ============================================================================
#  音效
# ============================================================================
#
# 播放机制见 `scripts/audio_fx.gd`（官方 `AudioStreamPlayer` +
# `AudioStreamPolyphonic`，一个播放器里并发播多条流）。
#
# ## 素材与「撞击力度」的分工
#
# 素材是 **Kenney**（CC0，可商用免署名），见 `assets/sounds/CREDITS.md`。
#
# Kenney 的文件名自带力度分级（`_light` / `_medium` / `_heavy`），
# 而且那三档是**按力度真实录制**的音频。所以分工是：
#
#   * `BOUNCE_TIERS` 用速度门限决定选**哪一档**；
#   * `streams` 指向的**族**代表材料（现在是 `impactPlate`＝金属板）；
#   * `pitch_soft/hard` 只做**小幅**修饰 —— 刻意收在 0.96~1.12，
#     大范围变调会连音色一起改，听上去像塑料，反而更假。
#
# 想换材料：把 `assets/sounds/ring_hit/` 里的文件换成别的族
# （Kenney Impact Sounds 还有 `impactMetal_*` / `impactWood_*` /
# `impactGlass_*` / `impactTin_*` / `impactMining_*`，同样各带三档），
# 再改下面的路径即可，脚本不用动。
#
# ## 格式：这里用的是 `.ogg`
#
# Godot 官方 Best practices 建议短促反复的音效用 WAV、长音频用 OGG。
# 本工程用 **Kenney 自带的 `.ogg`**，没有转成 WAV —— 转码需要额外解码器，
# 而这类几 KB 的一次性音效两者听感差别很小。
# 若日后要做精细的 loop 点编辑（只有 WAV 支持 loop end），再转不迟。
#
# ## 参数表
#
# | 键                    | 含义                                            |
# | --------------------- | ----------------------------------------------- |
# | `streams`             | 样本文件路径池；按文件名强度词自动分档           |
# | `pitch_jitter`        | 每次播放的音高抖动（±比例），防重复疲劳         |
# | `volume_db_soft/hard` | 音量（dB）。`_soft` 对轻撞、`_hard` 对重撞      |
# | `pitch_soft/hard`     | 音高（小幅）。撞得狠 → 略高略尖                 |

## 撞击力度的分档门限：`速度（世界单位/物理帧）` → 档名。
##
## 键名必须与 `audio_fx.gd::_tier_for_speed()` 遍历的顺序一致
## （light → medium → heavy，第一个「速度 < 上界」的档胜出）。
##
## ⚠️ 必须与 `ball.gd` 的速度**同尺度**（世界单位/物理帧，
##    见 `BALL_MIN_SPEED` 与 `BALL_LAUNCH_SPEED_*`）。开局初速约 3~6，
##    撞几次后升到 8 上下；`BALL_MIN_SPEED_MULT` 还会把过慢的球加速，
##    所以实际速度很少低于 1。据此把三档切开。
##    从别的引擎搬常数时先数量纲 —— 这条在本项目已经踩过一次。
const BOUNCE_TIERS := {
	"light": [0.0, 3.0],
	"medium": [3.0, 6.0],
	"heavy": [6.0, INF],
}

## ## `AUDIO` 为什么是 `static var` 而不是 `const`
##
## ⚠️ `PackedStringArray()` **不是常量表达式**，放进 `const` 会直接编译失败：
##
##     Parse Error: Assigned value for constant "AUDIO" isn't a constant expression.
##
## 而 `streams` 用 `PackedStringArray` 是刻意的 —— `audio_fx.gd` 按
## `PackedStringArray` 的类型标注去读它（`var paths: PackedStringArray = ...`）。
## 所以这里用 `static var`：同样是 `Config.AUDIO` 静态访问、有类型、可补全，
## 只是变成长度可变的普通数组（反正配置本来就是可改的）。
## 与 `PARTICLES` 的对比：那边全是数字/布尔，所以能当 `const`。

static var AUDIO := {
	# 球撞到圆环实心处 —— 出现最频繁的音效，重复疲劳也最容易在这里暴露。
	#
	# 15 条 `impactPlate_*`（light / medium / heavy 各 5 条）：
	# 由 `BOUNCE_TIERS` 按速度分档，档内等概率抽一条。
	"bounce": {
		"streams": PackedStringArray([
			"res://assets/sounds/ring_hit/impactPlate_light_000.ogg",
			"res://assets/sounds/ring_hit/impactPlate_light_001.ogg",
			"res://assets/sounds/ring_hit/impactPlate_light_002.ogg",
			"res://assets/sounds/ring_hit/impactPlate_light_003.ogg",
			"res://assets/sounds/ring_hit/impactPlate_light_004.ogg",
			"res://assets/sounds/ring_hit/impactPlate_medium_000.ogg",
			"res://assets/sounds/ring_hit/impactPlate_medium_001.ogg",
			"res://assets/sounds/ring_hit/impactPlate_medium_002.ogg",
			"res://assets/sounds/ring_hit/impactPlate_medium_003.ogg",
			"res://assets/sounds/ring_hit/impactPlate_medium_004.ogg",
			"res://assets/sounds/ring_hit/impactPlate_heavy_000.ogg",
			"res://assets/sounds/ring_hit/impactPlate_heavy_001.ogg",
			"res://assets/sounds/ring_hit/impactPlate_heavy_002.ogg",
			"res://assets/sounds/ring_hit/impactPlate_heavy_003.ogg",
			"res://assets/sounds/ring_hit/impactPlate_heavy_004.ogg",
		]),
		"pitch_jitter": 0.05,
		"volume_db_soft": -13.0,
		"volume_db_hard": -3.0,
		"pitch_soft": 0.96,
		"pitch_hard": 1.12,
	},
	# 球从缺口逃出、圆环碎裂 —— 玻璃碎裂，与「环是玻璃/能量环」的观感一致。
	# 事件音：刻意不随速度变化（`sfx_ring_break()` 不传档位，走整个池子）。
	"ring_break": {
		"streams": PackedStringArray([
			"res://assets/sounds/ring_break/impactGlass_medium_000.ogg",
			"res://assets/sounds/ring_break/impactGlass_medium_001.ogg",
			"res://assets/sounds/ring_break/impactGlass_medium_002.ogg",
			"res://assets/sounds/ring_break/impactGlass_medium_003.ogg",
			"res://assets/sounds/ring_break/impactGlass_medium_004.ogg",
		]),
		"pitch_jitter": 0.05,
		"volume_db": -2.0,
		"pitch": 1.0,
	},
	# 通关结算。用 `explosionCrunch` 的「轰」——霓虹场景配低频更有收束感。
	"celebrate": {
		"streams": PackedStringArray([
			"res://assets/sounds/celebration/explosionCrunch_000.ogg",
			"res://assets/sounds/celebration/explosionCrunch_001.ogg",
			"res://assets/sounds/celebration/explosionCrunch_002.ogg",
		]),
		"pitch_jitter": 0.0,
		"volume_db": -3.0,
		"pitch": 1.0,
	},
	# UI 按钮点击（START / APPLY / EXIT / 配色与取色模式按钮）。
	"ui_click": {
		"streams": PackedStringArray([
			"res://assets/sounds/ui_click/laserSmall_000.ogg",
			"res://assets/sounds/ui_click/laserSmall_001.ogg",
			"res://assets/sounds/ui_click/laserSmall_002.ogg",
		]),
		"pitch_jitter": 0.08,
		"volume_db": -8.0,
		"pitch": 1.0,
	},
}


# ============================================================================
#  离线渲染（Movie Maker mode）
# ============================================================================
#
# 用 `--write-movie <路径>` 启动即进入离线渲染：引擎把 delta 固定成 1/帧率，
# 渲染多快就写多快，**永不丢帧**，所以成片帧率是完美的。路径相对**项目目录**。
#
#     godot --path godot-ballgame --write-movie captures/round1.avi
#
# 本工程在 `project.godot` 里给 `physics/common/physics_jitter_fix` 配了
# `.movie` 特性标签覆盖（见下方 MOVIE_* 的说明），并把开局/结束接进了本模式，
# 所以上面这条命令**不需要** `--quit-after`，也**不需要**改任何滑块。
#
# ⚠️ 必须用**真实渲染器**。`--headless` + `--write-movie` 在 4.6.2 下会段错误
#    （dummy 渲染器给不出纹理），已实测。

## 固定随机种子。原版的开局方向、环自转方向、环初始角度、取色都走 `randi()`/
## `randf_range()`，不设种子的话每次渲染都是**另一局**，没法重渲同一个镜头。
## 换个数就是换一局；同一个数永远得到逐帧一致的同一局。
const MOVIE_SEED := 20260214

## 录够几局就自动退出。退出走 `get_tree().quit()`（引擎正常关闭），
## 只有这样 `MovieWriter._write_end()` 才会被调用、写出带时长信息的可用文件。
## ⚠️ 别用 F8 / Ctrl+C 打断，那样 AVI 会缺时长信息，剪辑软件打不开。
const MOVIE_ROUNDS := 1

## 录制时隐藏**制作工具**（配置侧栏 + 右上角按钮）。
## ⚠️ 顶部标题与 HUD **不**受它影响 —— 竖屏上下留白就是用来放那些字的，
##    它们是成片版式的一部分。见 `ui.gd::set_chrome_visible()`。
## 侧栏收起后 `_sync_camera()` 会让盘面用满整个宽度，所以构图与侧栏展开时不同。
const MOVIE_HIDE_UI := true

## 录制时是否让结算动画完整播完（不被「球飞出画面」提前打断）。
## 实时模式下球一飞出画面就跳过剩余结算，避免干等；录制时那是白丢镜头。
const MOVIE_FULL_CELEBRATION := true
