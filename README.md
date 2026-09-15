# 项目：godot-ballgame

`godot-ballgame/` 是把调研中发现的 P1（Darknife339/Ball-escape，pygame 原版） **按 Godot 官方设计原则重建**的版本：小球从同心旋转圆环的缺口中逐层逃出，
穿过一层就少一层，全部穿过即胜一局，播放庆祝动画后自动开下一局。

### 场景结构

```
main.tscn
├── World (Node2D)                       世界坐标域
│   ├── Camera2D                         世界→屏幕映射由它负责
│   └── Rings (Node2D)                   运行时按配置实例化 ring.tscn
├── ParticleFX     (particle_fx.tscn)    官方 GPU 粒子（碰撞反馈 / 碎环 / 拖尾）
├── CelebrationFX  (celebration.tscn)    官方 AnimationPlayer + GPU 粒子
├── PlayfieldLimiter (Area2D)            body_exited 信号 → 「球已飞出可见范围」
└── UI             (ui.tscn)             官方 Control 系节点 + 信号

ball.tscn     CharacterBody2D + Polygon2D + CollisionShape2D(CircleShape2D)

ring.tscn     Node2D
              ├── Visual          Polygon2D           显示弧带
              ├── SolidBody       StaticBody2D        反弹（碰撞层 ring）
              │   └── Arc0..3     CollisionPolygon2D  弧带扇段，BUILD_SOLIDS
              └── EscapeDetector  Area2D              逃出判定（掩码 ball）
                  └── Shell0..3   CollisionPolygon2D  逃出探测环壳，BUILD_SOLIDS

ui.tscn       CanvasLayer + Panel/VBoxContainer/HBoxContainer/GridContainer
              + Button(×47) / HSlider(×3) / Label(×11)

scripts/config.gd   ★ 所有可调参数集中在这里（class_name Config），详见下一节
```

`ring.tscn` 里 `SolidBody` 与 `EscapeDetector` 下的 **8 个多边形是脚本写进去的**
（`ring.gd::build_geometry()` 按每环的实际半径/缺口算），但**节点本身写在场景里** ——
所以场景在编辑器里打开就是**完整、可检视、无「没有形状子节点」警告**的。
场景文件由 `tools/build_ring_scene.gd` 生成（它调用的是和运行时**同一份**
`build_geometry()`，所以不可能对不上）；几何算法改了要重新跑一次：

```powershell
& $exe --path godot-ballgame --headless --script res://tools/build_ring_scene.gd
```

### 改参数去哪改

**所有可调参数集中在 `godot-ballgame/scripts/config.gd`（`class_name Config`）这一个文件里。**

| 想改什么 | 位置 |
| --- | --- |
| **盘面占画面宽度的比例** / 环心位置 / 侧栏宽 / 出界判定松紧 | `Config.PLAYFIELD_FILL`、`Config.WORLD_CENTER`、`Config.SIDEBAR_WIDTH`、`Config.PLAYFIELD_MARGIN` |
| 竖屏留白处文字的竖直位置（标题 / HUD / 结算） | `Config.LAYOUT_*_Y`（占视口高度的比例） |
| 环：半径与递增量、厚度、默认缺口、弧带细分、自转扫掠上限、探测壳厚度、破环线 | `Config.RING_*` |
| 球：半径、细分、弹性、加速阈值、初速、重力 | `Config.BALL_*` |
| 默认玩法（环数 / 转速 / 缺口 / 重力 / 取色） | `Config.DEFAULT_CFG` |
| 取色板 / 单色表 / UI 配色 / 字号 | `Config.PALETTES`、`Config.BASE_COLORS`、`Config.UI_*`、`Config.FONT_*` |
| 侧栏三个滑块的**范围 / 步进 / 标签 / 格式** | `Config.SLIDERS` |
| 粒子数值 | `Config.PARTICLES`（`particles.cfg` 是可选的临时覆盖） |
| 结算动画时长 / 淡出点 / 文字色 / 字号 / 弹出曲线 / 彩屑数量 | `Config.CELEBRATION_*` |
| 音效：素材路径、音量、音高抖动、并发预算 | `Config.AUDIO`（见「音效」一节） |
| 离线渲染：录几局 / 随机种子 / 隐藏工具 / 结算播完 | `Config.MOVIE_*` |
| 场景路径 | `Config.SCENE_*` |

**刻意不放在 `config.gd` 的参数**（避免同一个值有两处定义）：

- **视口尺寸与拉伸模式** → `project.godot`（Godot 官方位置，引擎直接读）。
  改分辨率就来这里，见「竖屏版式」一节。录制期间才生效的覆盖也在这里，
  写成带 `.movie` 后缀的键（官方 feature tag 机制）。
- 颜色渐变、缩放曲线等观感 → 各自的 `.tscn`（要在编辑器里可视化预览）。
- 控件间距、最小宽高 → `ui.gd` 的构建函数（就地读更清楚）。

`.tscn` 里那些数字（`main.tscn` 的相机 zoom、`ball.tscn` 的 `CircleShape2D.radius`、
`particle_fx.tscn` 的 `amount`……）现在只是**编辑器预览值**：运行时一律被 `config.gd`
覆盖。所以不用担心两边不一致。

> ⚠️ `Config` 里的 `const` 字典/数组在 Godot 4 里是**只读**的，
> 要一份可改的副本时先 `.duplicate()`。

> ⚠️ 改了 `Config` 里的**环几何**参数（半径 / 厚度 / 缺口 / 细分数 / 球半径）之后，
> 要重跑一次场景生成脚本，让编辑器里的预览跟上：
>
> ```powershell
> & $exe --path godot-ballgame --headless --script res://tools/build_ring_scene.gd
> ```
>
> **不需要**为改分辨率或 `PLAYFIELD_FILL` 重跑 —— 顶点是世界单位，缩放由相机承担。

### 与「逐行翻译 pygame」相比的三处结构性改动

- **环的反弹体必须是 `PhysicsBody2D`** —— `Area2D` 挡不住 `move_and_collide()`。
  但形状用的是官方 `CollisionPolygon2D`（每段一个**简单**扇段），不是手切凸块：
  见「移植时修掉的问题」第 5 条，早先「凸分解不可用」的结论**过度概括**了，
  真正失败的是自交多边形。
- **数值参数用官方 `HSlider`**，不是自写的「−/+」按钮 —— 滑块天生带范围钳制、
  步进、键盘操作与拖拽。
- **「球逃出环」是物理事件**（`Area2D.body_entered`），不是每帧的几何谓词 ——
  见第 7 条。

### 四个 key design 决定

**1. 世界→屏幕映射交给官方 `Camera2D`，不再手写 `world_to_screen()`。**

旧实现在每个绘制、每个粒子位置里手动调用缩放与侧栏偏移，任何一处漏乘 `current_scale` 就错位（实测踩过 350px 的固定偏移，以及粒子与碰撞位置不符）。
现在所有节点都在世界坐标下工作，转换由引擎负责。侧栏显隐只改相机 `offset`（屏幕像素，需除以 `zoom` 换算成世界单位）：

```gdscript
_camera.zoom = Vector2(0.7, 0.7)
var shift_px := -300.0 * 0.5 if sidebar_on else 0.0
_camera.offset = Vector2(-shift_px / 0.7, 0.0)
```

实测（真实渲染器，视口 1350×950）：

|           | 世界中心(500,500) → 屏幕 | 可见区中心 | 内容包围盒 x                |
| --------- | ------------------ | ----- | ---------------------- |
| 菜单（侧栏隐藏）  | (675.0, 475.0)     | 675.0 | [360..990] ⊆ [0..1350] |
| 游戏中（侧栏显示） | (525.0, 475.0)     | 525.0 | [210..840] ⊆ [0..1050] |

**2. 圆环的「显示几何」和「碰撞几何」是同一份数据。**

`ring.gd::build_geometry()` 生成唯一一份弧带顶点，同时喂给 `Polygon2D`、
`SolidBody` 的 4 个 `CollisionPolygon2D`、`EscapeDetector` 的 4 个
`CollisionPolygon2D`。所以「画出来的环」和「能撞到球的环」**在结构上不可能不一致**。
实测碰撞接触点半径 `65.076`，环带内沿 `65.100`，**误差 0.024 像素**。

几何**只在入树时构建一次**：局部几何不随朝向变化，自转完全交给节点 `rotation`。
（旧实现每帧把 `angle_deg` 又写进局部顶点，与节点旋转叠加 —— 观感转速其实是配置值
的 **2 倍**，还每帧重写一次全部形状。现在两者都没有了。）

**3. 缺口就是碰撞几何里的一段空缺。**

球的 `move_and_collide()` 走到缺口处自然没有碰撞、直接穿过；走到实心处自然拿到
碰撞法线。**不需要任何角度判定**。旧实现在渲染和碰撞里各写了一套极坐标角度判断，
两套算法不一致就直接导致错位。

**4. 「逃出」用官方 `Area2D` 事件，不用每帧的位置谓词。**

`EscapeDetector` 是贴在弧带外侧的**整圈**环壳，内沿半径 = 破环线 + 球半径，
于是 `body_entered` 恰好等于「球的**圆心**越过破环线」，与 pygame 原版
`dist > r + thickness/3` 逐字对应。

**它不是「缺口形状」，也刻意不做角度判断** —— 因为角度判断正是最初卡死的根源
（第 7 条）。缺口已经由 `SolidBody` 的洞强制了：球要从环内到环外只能走那个洞，
所以「越过破环线」本身就蕴含「从缺口穿出」。

### 移植时修掉的问题

1. **`SystemFont` 没有 `font_size` 属性** —— 赋值会抛 `Invalid assignment of property` 并中断 `_ready()`。（新版已经改用 `Control` + `add_theme_font_size_override`）
2. **画出来的开口与物理开口错开 55°** —— `_draw_thick_arc` 画的是 `[angle, angle+360-gap]`，物理缺口却是 `[angle, angle+gap]`。两者弧长都是 305°，
   但整条环被转了一个 `gap_size`：
   实测（角度扫描，r=100/gap=55）物理可穿越区是 `[0..55]`，而画出来的开口在 `[305..360]` —— 于是小球**在看得见的实心处穿过去把环打碎，在看得见的缺口处反而
   被弹回来**。已改为从 `angle + gap` 画到 `angle + 360`（与 pygame 原版第 88 行一致）。
3. **碰撞带比画出来的环宽 3.9 倍** —— 碰撞用世界单位 `thickness/2 = 7`，渲染却乘了 `current_scale`（4.9）；再加上球半径在两侧各撑开 12px，实测碰撞带 `[81, 119]` vs 画出来的 `[95.1, 104.9]`，接触点偏出环沿 **14.1 世界px = 9.87 屏幕px**。
   现在两者共用 `r_inner`/`r_outer`。
4. **小球速度指数爆炸** —— 「速度过小就加速」的阈值原版按**像素/帧**取 1.0，
   而内部速度是世界单位/帧（≈3），于是每帧都低于阈值、每帧乘 1.1。
   实测 3000 帧后球距环心涨到 **18 万像素**。阈值必须与速度同尺度。
5. **`CollisionPolygon2D` 的凸分解只对「自交多边形」失效** —— 早先把整条 305°
   弧带作为**一个**多边形交给 `SOLIDS` 模式，它会调
   `Geometry2D.decompose_polygon_in_convex()`。实测沿环带扫一圈，有的角度查到
   2 个分块、有的查到 **0 个**，球会从某些「实心」位置直接穿过去。
   （`SEGMENTS` 线段模式更不行：只生成线，整条环带没有实体。）
   > ⚠️ 当时据此写下的结论**过度概括**了。后来补测发现，真正失败的原因是那种
   > 多边形**自交**。把弧带切成 4 个**简单**（非自交）扇段后，**同一个官方节点**
   > 分解得完全正确：实测 54 组参数组合（半径 100/450 × 缺口 20°/55°/150° ×
   > 扇段数 1/2/3/4/6/8/12/48 × 外加手切凸块对照组），逐探针与显示多边形比对，
   > **真实分歧全为 0**（只有贴边界的浮点分歧）。
   > 所以现在用回官方 `CollisionPolygon2D`：**4 个节点取代 48 个
   > `CollisionShape2D` + 手写凸切**。
6. **`Animation` 的 Call Method 轨道自节点路径要写 `"."`** —— 写成 `^":"` 归一化后是
   空路径，`AnimationMixer` 每帧刷 `couldn't resolve track: ''`（实测几千行）。
7. **「逃出环」不能做成每帧的位置谓词**（用户报的「球穿过圆环、环却不消失」）——
   旧实现让球每帧用 `gap_admits()` 判「我现在是不是既在环外、又整个角度跨度都在
   缺口内」。球从缺口穿出的那一帧，它的角度常**贴着缺口边缘**（球半径在环上张开
   ±6.4°），判据当场为假；之后球只会越飞越远、环还在自转，判据长期为假 ——
   于是环**永远不碎**。而 `main._process()` 要求全部环清空才结算，**整局永久卡死**。
   改成 `Area2D` 事件后，「穿过缺口」与「碎环」是同一个物理事件的两个面。
   实测 600 次随机自由对撞（缺口 20°/55°/90°/150°、自转 ±8°/帧）
   + 30000 帧整局连跑（含 15 环极限配置）：**「越过破环线却没碎」= 0**。
8. **`StaticBody2D` 的运动没有连续碰撞检测 —— 环转太快会把球从实心处顶出去** ——
   球自己是用 `move_and_collide()` 扫掠的，球速不是问题；出问题的是
   **环壁一步跳到新位置**。一步之内压进球的深度超过「球心到最近那条外弧的距离」时，
   接触的最近面会从缺口的**径向切面翻成外弧**，解算于是沿外法线把球推出环外 ——
   实测单步跳 ~9px，球心从 `<73.3` 直接出现在 `81.9`，肉眼就是「球穿过了实心环壁」。
   现在把每帧**切向扫掠**夹在环带半厚以内（`ring.gd::MAX_SWEEP_HALF_THICKNESS`）。
   实测最严苛档（自转 8°/帧）600 次对撞：**不限扫掠时 20 次穿模，限制后 0 次**。
   另外探测环壳也刻意做**厚**（8 倍球半径）：解算的弹出一跳能达几十像素，
   薄壳会被整个跨过去 —— 于是球到了环外、环却没碎，又回到「整局卡死」。
   > 副作用：外圈环的**角速度**会低于配置值（各环边缘线速度趋于一致）。
   > 默认参数下内两圈不受影响，最外圈约降到配置值的 1/3。想让外圈转得更快就调大
   > `MAX_SWEEP_HALF_THICKNESS`，代价是重新暴露上面的穿模。
9. **`Area2D` 信号回调里不能改物理状态** —— `PlayfieldLimiter.body_exited` 是物理
   信号，在它的回调里直接 `start_round()` 重建圆环，会让新环的
   `CollisionPolygon2D.polygon` 赋值撞上物理查询刷写：
   `ERROR: Can't change this state while flushing queries.`，而且形状可能根本没
   注册上（环成了没有碰撞的空壳）。现在这条路径一律 `call_deferred`，并靠
   `state` 自己兜住重复调用。
   > **这个 bug 只在真实渲染器下暴露** —— headless 的视口只有 64×64，
   > 出界判定区被算得极小、`body_exited` 根本不触发。见「验证方法」第 7 条。
10. **`ParticleFX.emit_trail()` 从来没被调用过** —— 官方拖尾发射器不会跟球走，
    一直留在初始位置原地发射。已由 `main._process()` 每帧调用。
11. **`CelebrationFX.set_amounts()` 从来没被调用过** —— 彩屑数量一直只认
    `celebration.tscn` 里的值。现在 `_ready()` 会用 `Config.CELEBRATION_*_AMOUNT` 调它。
12. **`particle_fx.gd` 在「覆盖文件缺某个 section」时会跳过整个初始化** ——
    原逻辑是 `if _cfg.has_section(s): _apply(...)`，于是没有那段配置时
    `one_shot` 没人写、一次性发射器没被静音，会在场景原点自行发射。
    改成**三个发射器无条件初始化**，逐键回落（`particles.cfg` > `Config.PARTICLES`
    > 场景值）。

### 旋转环的碰撞精度（实测）

之前只验证过静态环，旋转环曾标注为「推断、未实测」。现已补测：

| 自转速度             | 碰撞次数 | 接触点半径范围（环带 275.100..284.900） | 局部系法线·径向 最差 | 最大嵌入      |
| ---------------- | ---- | ---------------------------- | ----------- | --------- |
| 3.0 度/帧（游戏内 1.8） | 19   | 284.372 .. 284.880           | **0.9982**  | 0.0790 px |
| 15.0 度/帧（8 倍压力）  | 6    | 284.398 .. 284.541           | **0.9994**  | 0.0167 px |

**结论：旋转体的碰撞法线完全准确，没有滞后。**（最大嵌入 0.079 px 正好是 `move_and_collide()` 的 `safe_margin=0.08`，属正常解算，不是错位。）

> 排查备忘：第一次测出「点积 0.9879 → 0.8259，法线严重滞后」是**我的参照系错了** —— `get_normal()` 是**世界系**法线，我却拿它跟环**局部系**的径向比，环在自转就凭空
> 多出一个 `rotation` 偏差，且随球的飞行延迟累积。转成 `normal.rotated(-ring.rotation)` 后点积变成 `1.0000`。

### ⚠️ Godot 的 `Vector2.reflect()` 不是标准反射

pygame 原版用 `v_vel.reflect(-n)` 做弹墙，若在 Godot 里原样照搬会**完全不反弹**：

| 输入                   | Godot `v.reflect(n)` | 标准公式 / pygame |
| -------------------- | -------------------- | ------------- |
| `v=(3,4)`, `n=(0,1)` | `(-3, 4)`            | `(3, -4)`     |

Godot 的版本翻的是**切向**分量，而标准 `v - 2(v·n)n` 翻的是**法向**分量；
更坑的是它**忽略法向量的正负号**（`reflect(n)` 与 `reflect(-n)` 返回同一个值）。

现在直接用官方的 `Vector2.bounce(n)` —— 它**就是**标准镜面反射 `v - 2(v·n)n`，不需要自己写公式。

> 排查手法备忘：当时用「逐子步模拟 + 打印 `dist`/`vel`/`dot`/走哪个分支」定位到
> 碰撞分支**疯狂触发**（270 次）但**径向速度零次反向**（`radial_reversals=0`），
> 才把嫌疑锁定到 `reflect` 本身。

---

## 粒子特效（全部使用 Godot 官方节点）

粒子由 **`GPUParticles2D` + `ParticleProcessMaterial`** 实现，场景在 `godot-ballgame/particle_fx.tscn`，参数覆盖文件是 **`godot-ballgame/particles.cfg`**（改完重启生效）。

```
ParticleFX (particle_fx.tscn)    直接挂在世界坐标下（相机负责换算）
├── Burst      GPUParticles2D  球撞到圆环实心处的碰撞反馈
├── RingBreak  GPUParticles2D  球从缺口逃出、圆环碎裂
└── Trail      GPUParticles2D  小球运动轨迹（trail_enabled 官方拖尾）
```

`scripts/particle_fx.gd` 只做三件事：把 cfg 参数套到节点属性上、在正确的世界
位置触发一次性爆发、每帧把拖尾发射器挪到球的位置。发射/生命周期/阻尼/重力/
缩放曲线/颜色渐变全部交给引擎。**编辑器里打开 `particle_fx.tscn` 即可可视化调参**。

> 颜色渐变、缩放曲线等观感项留在场景里；`particles.cfg` 只覆盖它显式写出的键，
> 没写的沿用场景值，避免配置文件的遗漏项清掉编辑器里调好的效果。

### ⚠️ 渲染器必须是 forward_plus

实测：`gl_compatibility` 渲染器**不支持粒子拖尾**，运行时会打印 `WARNING: The Compatibility renderer does not support particle trails.`， `trail_enabled = true` 完全失效（画面无任何拖尾）。另外 `GPUParticles2D.emit_particle()` 也只在 Forward+ / Mobile 下可用。

### 拖尾参数怎么标定

球的屏幕速度只有约 **3px/帧**，这个量级下粒子参数很容易调成「看不见」。
标定方法与实测值：

- 用**最小受控实验**（单独一个 `GPUParticles2D`，发射器沿直线移动，无球无环）
  量「发射器后方轨迹延伸像素」。
- 实测 `amount=160 / lifetime=1.2 / velocity=20..80` → 轨迹延伸约 **106px**。
- 注意两个联动关系：
  1. `trail_lifetime × trail_sections` 决定官方拖尾的采样间隔，太粗会变成虚线；
  2. 粒子在屏上的尺寸 ≈ `scale_max × lifetime`（像素），所以改 `lifetime` 必须同步改 `scale`。

---

## 音效（官方音频节点 + `AudioStreamPolyphonic`）

场景在 `godot-ballgame/audio_fx.tscn`，脚本 `scripts/audio_fx.gd`，
参数在 `scripts/config.gd` 的 **`Config.AUDIO`**。

```
AudioFX (audio_fx.tscn)
└── Player  AudioStreamPlayer   stream = AudioStreamPolyphonic(polyphony=32)
```

### 为什么是「一个 Player + `AudioStreamPolyphonic`」

一次撞碎多个环时，好几个撞击音**落在同一帧**。普通 `AudioStreamPlayer` 的
`play()` 会把上一次**截断**（只剩最后一个出声）。官方解法就是
`AudioStreamPolyphonic`：一个播放器里并发播任意多条流，而且
**音量与音高是逐条传的**（不会互相踩）：

```gdscript
var pb := _player.get_stream_playback() as AudioStreamPlaybackPolyphonic
pb.play_stream(sample, 0.0, volume_db, pitch_scale)
```

### 「悦耳」的关键：每次撞击都略有不同

不是靠素材多，而是靠**两个层次的随机**。力度取**反弹之前**的速度
（`ball.gd::_handle_collision`，随 `bounced` 信号传出）。

**第一层：按速度选「档」，不是靠变调。**
Kenney 的文件名自带力度分级（`_light` / `_medium` / `_heavy`），
而且那三档是**按力度真实录制的音频**。`audio_fx.gd` 从文件名认出档位，
按 `Config.BOUNCE_TIERS` 的门限选档，档内等概率抽一条：

| 速度（世界单位/物理帧） | 档 | 样本 |
| --- | --- | --- |
| < 3.0 | `light` | `impactPlate_light_000..004` |
| 3.0 ~ 6.0 | `medium` | `impactPlate_medium_000..004` |
| ≥ 6.0 | `heavy` | `impactPlate_heavy_000..004` |

**第二层：档内小幅渐变 + 抖动。** 音量 −13 → −3 dB，
音高只动 **0.96 → 1.12**（刻意收窄）+ `pitch_jitter`。

> ⚠️ 音高刻意**不**承担「力度」这件事。大范围变调会连音色一起改，
> 听上去像塑料 —— 力度交给真实录音的档位，变调只做修饰。
>
> ⚠️ 音量映射是**线性**的，**不要**照搬「动能 ∝ v²」。拿速度平方去调音量，
> 轻撞会弱到听不见、重撞又全部撞顶，听感反而更差。

**这个机制对命名有依赖**：`audio_fx.gd::_intensity_of()` 从文件名找
`light` / `medium` / `heavy`；找不到的归入 `any` 档（该档没有样本时
回落到全部样本，所以「只丢一条没分级的声音」也能正常响，不会静音）。

### 并发预算用「滚动时间窗」，不是「每帧」

同一时间窗（`VOICE_WINDOW_USEC = 50ms`）内最多 4 条 voice，超出的丢弃，挡住削顶。

> ⚠️ 这里**踩过坑**：最初写成「每帧最多 4 条」，结果**完全失效** ——
> 一帧内的 N 次撞击全发生在 `_process()` 清零之后，计数在帧内根本涨不起来。
> 实测连发 10 次计数仍是 0，一条都没丢。详见 `.dsh/skills/godot-project/examples.md` 案例 24c。

### 素材：Kenney，全部 CC0

两个包（**Impact Sounds** 130 个、**Sci-fi Sounds** 80 个）放在
`godot-ballgame/assets/sounds/`，选了 26 个按用途分目录：

```
assets/sounds/
├── kenney_impact-sounds.zip     原始包（保留，便于换素材）
├── kenney_sci-fi-sounds.zip
├── CREDITS.md                   来源与许可记录
├── ring_hit/     15  impactPlate_{light,medium,heavy}_*   球撞环实心处
├── ring_break/    5  impactGlass_medium_*                 环碎裂
├── celebration/   3  explosionCrunch_*                    通关结算
└── ui_click/      3  laserSmall_*                         UI 按钮
```

**全部 CC0**（可商用、可改、**无需署名**）。路径在 `Config.AUDIO` 里逐个列出；
换材料只需换目录里的文件，脚本不用动（只要保住 `_light/_medium/_heavy` 命名）。

> ⚠️ **改完素材要跑一次导入**，否则 `ResourceLoader.exists()` 全部返回 false
> 并刷一屏「音频文件不存在」：
>
> ```powershell
> & $exe --path godot-ballgame --headless --import
> ```
>
> `.ogg` 需要生成 `.import` 与 `.godot/imported/` 才能被运行时加载。
> 注意：这条命令**输出接管道时看起来会中途退出**（实测停在 22/26 个文件、
> `exit=-1`），其实是因为进度条输出被管道处理干扰 —— **不接管道重跑就是
> `exit 0`，26 个文件全部导入成功**。别被那个假退出码骗了。

格式说明：这里用的是 **Kenney 自带的 `.ogg`**，没转 WAV。Godot 官方
Best practices 建议短促反复的音效用 WAV（原话 "WAV for short and repetitive
sound effects"），但两者在这类几 KB 的一次性音效上听感差别很小；
只有需要精细 **loop 点编辑**时（WAV 才支持 loop end）才值得转。
素材调研与许可讨论见仓库根目录 `research/04_音效素材来源与Godot音频方案.md`。

### Master 总线上的硬限幅器（`default_bus_layout.tres`）

同时撞碎多个环时几条撞击音会在同一帧叠加。实测录出的 AVI 音轨**峰值达到满量程
32768**，有 7 个削顶样本（RMS −26 dBFS 正常，只有峰值撞顶）——
听觉上几乎听不出，但那是硬削波。所以 Master 上挂了一个
**`AudioEffectHardLimiter`**（天顶 −0.3 dB），从结构上消除这个问题。

> ⚠️ 用 `AudioEffectHardLimiter` 而**不是** `AudioEffectLimiter` ——
> 后者在 4.6 已标记 **Deprecated**（本地离线文档原文
> "Deprecated: Use AudioEffectHardLimiter instead."）。

`default_bus_layout.tres` 由 `tools/make_audio_bus.gd` 生成（不是手写的）。
重跑生成脚本前**先删掉已有 `.tres`** —— `--script` 启动时引擎会先加载它，
不清空的话效果器会一层层**叠加**（实测跑三次变成 3 个限幅器）。

另外：`AudioBusLayout` **没有任何成员**（`bus_count` 是 `AudioServer` 的属性），
所以校验要看**引擎运行时的实际值**，不能去读 `.bus_count`，也不该只看
`.tres` 里有没有那一行 —— `ceiling_db` 等于默认值 0.0 时引擎就不序列化它。

### ⚠️ 录制时引擎会**写出**一条 WAV，别把它当素材读回来

`--write-movie captures/x.png` 会在写出 PNG 帧序列的同时，
**附赠一条同名的同步音轨 WAV**（官方 MovieWriter 行为，见
`class_moviewriter` 本地文档：`.png` → "PNG image sequence for video and WAV for audio"）。
那是**输出**，与同一个引擎时钟产出，所以后期与画面天然对齐，不需要手动对点。

Video 格式的选择：

| 扩展名 | 视频 | 音频 | 备注 |
| --- | --- | --- | --- |
| `.avi` | MJPEG | **PCM（已实测确认有音轨）** | 大多数播放器可放；4 GB 上限 |
| `.ogv` | Theora | Vorbis | 浏览器不支持 Theora，发抖音仍要转码 |
| `.png` | PNG 序列 | 同名 `.wav` | 无压缩，最慢，交给 FFmpeg 合成 |

---

## 竖屏版式（1080×1920，9:16）

这个项目**不是拿来玩的**，是拿来出片的，所以版式直接按竖屏成片来做：
抖音 / B站竖屏标准 **1080×1920**，盘面撑满宽度，上下留白放文字。

### 视口与出片分辨率

`project.godot`：

```ini
[display]
window/size/viewport_width=1080
window/size/viewport_height=1920
window/size/window_width_override=540     ; 预览窗口，1080×1920 放不进 1080p 屏幕
window/size/window_height_override=960
window/stretch/mode="viewport"            ; 见下面的说明
window/stretch/aspect="keep"
```

> ⚠️ **必须是 `viewport` 拉伸模式**。官方文档：`disabled` / `canvas_items` 下
> **出片分辨率由窗口尺寸决定**，那样 1080×1920 会被屏幕高度卡住、录不出全尺寸；
> 只有 `viewport` 下由**视口**决定（"The size of the root Viewport is set precisely
> to the base size specified in the Project Settings"）。
> 窗口 override 只影响屏幕预览，不影响成片。

### 构图怎么定的

实测（1080×1920，默认 8 环）：

| 项目 | 实测值 |
| --- | --- |
| 相机 zoom | `1.08709` |
| 盘面屏幕直径 | `993.6` px |
| **占视口宽度** | **92.0%**（= `Config.PLAYFIELD_FILL`） |
| 占视口高度 | 51.7% |
| 上下留白 | 各 `463.2` px（合计 48.3% 高度） |
| 盘心 vs 视口中心 | 偏心 `(0.0, 0.0)` px |
| 球屏幕半径 | `13.05` px |

留白里放三样东西，位置都是**占视口高度的比例**（`Config.LAYOUT_*_Y`），
所以换成 1440×2560 也成立：

- 顶部 `LAYOUT_TITLE_Y = 0.072` → `y=138`：游戏名 `BALL ESCAPE`
- 顶部 `LAYOUT_HUD_Y = 0.145` → `y=278`：HUD（Wins 计数）
- 底部 `LAYOUT_CELEBRATION_Y = 0.855` → `y=1642`：结算文字 `ESCAPED!`
  （彩屑受重力往下落，正好落在它周围）

**盘面占多少宽度**由 `Config.PLAYFIELD_FILL` 控制，相机 zoom 由它**反推**：

```gdscript
var zoom := area_w * Config.PLAYFIELD_FILL / _disc_diameter()
```

所以换分辨率不用改构图 —— 想让盘面更大/更小只改这一个数。

### ⚠️ 修掉的两个取景 bug（旧版横屏时就有）

改竖屏时量了一下旧版的实际取景，发现它本来就是坏的：

| 症状 | 原因 |
| --- | --- |
| 盘面只占画面宽的 **33%**（448px 直径） | 「世界→屏幕」缩放被乘了**三次**：几何里 `×0.7`、球位移 `×0.7`、相机 zoom 又 `×0.7`，净 `0.49` |
| 盘面整体偏离画面中心 `(-105, -105)` px | 内容放在 `WORLD_CENTER × WORLD_SCALE` = (350,350)，相机却看 `WORLD_CENTER` = (500,500)，差 150 世界单位 × zoom 0.7 = 105px |

改法不是打补丁，而是**把坐标系统一起来**：

- **顶点与物理全部是世界单位**，不含任何屏幕缩放（`ring.gd::build_geometry()` 不再收 `p_scale`）。
- **世界→屏幕只由 `Camera2D.zoom` 承担一次**，由 `main.gd::_sync_camera()` 按
  「盘面直径 ÷ 可见区宽度」反推。
- **内容与相机共用 `Config.WORLD_CENTER`**，所以盘心必然落在视口中心。
- 顺带删掉了 `Config.WORLD_SCALE` —— 它同时表示「几何缩放」和「相机 zoom」两件事，
  正是上面两个 bug 的温床。

> 另一个副作用：**改分辨率不再需要重跑 `ring.tscn` 生成脚本**。
> 旧版把缩放烤进顶点，所以动一下缩放就得重新生成场景；现在顶点与缩放无关。

---

## 离线渲染（Movie Maker mode，出片用）

Godot 官方的**非实时**录制：引擎把每帧 `delta` 钉成 `1/帧率`，渲染能跑多快就写多快，
**永不丢帧**，所以成片帧率是完美的，且与硬件快慢无关。这是官方功能，不是我们写的。

### 一条命令出片

```powershell
$exe = 'E:\Godot\Godot_v4.6.2-stable_win64\Godot_v4.6.2-stable_win64_console.exe'
$env:APPDATA = 'D:\lg\else\videos-godot\.godot-userdata'   # 沙箱里必须，否则引擎起不来

# 录一整局（到结算动画播完自动停），默认 60fps
& $exe --path godot-ballgame --write-movie captures/portrait.avi
```

**不需要** `--quit-after`，也**不需要**动任何滑块 —— 工程已经接好了：

- 靠官方 feature tag `movie`（`OS.has_feature("movie")`，由 `--write-movie` 自动置上）
  判定「正在录制」，**跳过主菜单直接开球**，否则录出来前半段是菜单。
- 每局结束（结算动画播完）时 `get_tree().quit()` 自己退出。
  **必须让它正常退出**：只有引擎正常关闭，`MovieWriter._write_end()` 才会被调用、
  补上文件头与时长信息。用 F8 / Ctrl+C 打断会写出缺时长信息的 AVI，剪辑软件打不开。
- 录制时固定随机种子，**同一 `seed` 逐帧一致**（实测两次独立渲染 SHA256 完全相同）。
- 录制时隐藏**制作工具**（配置侧栏 + 右上角按钮）；
  顶部标题与 HUD 保留 —— 它们是竖屏留白处的成片文字。

想录多局改 `Config.MOVIE_ROUNDS`；想换一局改 `Config.MOVIE_SEED`。

### 参数在哪

| 想改什么 | 位置 |
| --- | --- |
| 录几局后自动退出 / 随机种子 / 是否隐藏制作工具 / 是否让结算播完 | `Config.MOVIE_*` |
| 输出帧率 | `--fixed-fps 30`，或 Project Settings 的 `editor/movie_writer/fps`（默认 60） |
| 输出分辨率 | = 视口尺寸 **1080×1920**（见「竖屏版式」）；改 `project.godot` 即可 |
| 编码质量 / 关键帧间隔 / 音频 | Project Settings 的 `editor/movie_writer/*` |
| 录制期间才生效的项目设置覆盖 | `project.godot` 里带 `.movie` 后缀的键 |

### ⚠️ 必须用真实渲染器

`--headless` + `--write-movie` 在 4.6.2 下**直接段错误崩溃**
（`texture_2d_get` 拿到空纹理，dummy 渲染器给不出画面）：

```
ERROR: Parameter "t" is null.  at: texture_2d_get (.../storage/texture_storage.h:106)
CrashHandlerException: Program crashed with signal 11
```

所以录制**不能**图快去加 `--headless`。

### ⚠️ `physics_jitter_fix` 会让 delta 不固定（已用官方机制修掉）

`physics/common/physics_jitter_fix`（默认 `0.5`）为了让物理时钟迁就真实时间，会
**微调每帧 `delta`**。实测 `--fixed-fps 30` 时它让 delta 在 `0.032500 ~ 0.033333`
之间抖（spread `8.33e-4`）—— 离线渲染要的就是严格确定，这个抖动必须去掉。
60 / 120fps 恰好奇妙地躲过了（spread `0`），所以很容易一直发现不了。

修法用的是官方给的 **feature tag 覆盖项目设置**机制，写在 `project.godot`：

```ini
[physics]
common/physics_jitter_fix.movie=0.0
```

置 0 后 delta 恒等于 `1/帧率`（spread `0`，任意帧率都成立），而**实时游玩仍是 0.5**，
手感一点没变。实测：

| 模式 | `Engine.physics_jitter_fix` | delta spread |
| --- | --- | --- |
| 实时 `--fixed-fps 30` | 0.5 | 8.33e-4 |
| 录制 `--write-movie --fixed-fps 30` | 0.0 | **0** |

### 格式怎么选

| 格式 | 说明 |
| --- | --- |
| `.avi`（MJPEG） | 默认选择。编码快、兼容广，**限制 4GB**。实测 1350×950 约 40KB/帧 → 60fps 下约 28 分钟上限，一局 36 秒完全够 |
| `.png`（序列帧 + `.wav`） | 无损、支持透明，但要外部 ffmpeg 再编码，体积大 |
| `.ogv`（Theora） | 压缩率更好，但**只有编辑器版能录**，且浏览器不支持 |

> ⚠️ 实测 AVI 的 RIFF 大小字段比实际文件**少 70 字节**（180 帧和 2161 帧都一样，
> 是固定偏差，`idx1` 索引块结尾正好落在 EOF，结构完整）。ffmpeg 能把 2161 帧
> 全部解出来，确认无害，知道有这回事即可。

### 转 MP4（本机没有独立 ffmpeg，用剪映自带的）

本机没装 ffmpeg，但**剪映自带一个**（无软件 x264，有 `h264_nvenc`）：

```powershell
$ff = 'E:\JianyingPro\11.4.0.14410\ffmpeg.exe'
& $ff -y -i godot-ballgame\captures\round.avi `
      -c:v h264_nvenc -preset p5 -rc vbr -cq 19 -b:v 0 `
      -pix_fmt yuv420p -movflags +faststart `
      godot-ballgame\captures\round.mp4
```

它属于剪映的安装目录，剪映升级后路径会变 —— 要长期用建议自己装一份正规 ffmpeg。
实测输出：`Duration 00:00:36.02 / 1350x950 / 60 fps / h264 Main + aac`。

### 想录比屏幕还高的分辨率

`disabled` / `canvas_items` 拉伸模式下，输出分辨率由**窗口**尺寸决定。要超过屏幕：

```powershell
& $exe --path godot-ballgame --write-movie captures/round.avi --resolution 1920x1080
```

更高就用 `viewport` 拉伸模式（由视口尺寸决定输出），配合
`Display > Window > Size > Window Width/Height Override` 把实际窗口压小 ——
两者都能用 `.movie` 特性标签只对录制生效。

---

## 验证方法（不要只看截图）

用户已明确要求：**涉及视觉效果时不要依赖截图，以人的观察为准**。所以本项目的
验证全部走数值化。用的是**一次性 harness 场景**（`godot --headless res://_xxx.tscn`
可以直接指定跑哪个场景，不必改 `project.godot` 的 `[autoload]`）。

1. **脚本错误**：`--headless --quit-after N`，确认 `SCRIPT ERROR` / `Parse Error` 为 0。

2. **几何一致性**：让「显示多边形」和「碰撞体」逐点对拍 —— 在环带内外扫一圈探针，
   每点同时问物理（`PhysicsDirectSpaceState2D.intersect_point`）和几何
   （`Geometry2D.is_point_in_polygon`）。判据是**真实分歧**（离多边形边界 > 0.1px
   的不一致）必须为 0；贴边界的浮点分歧不算。实测 54 组参数组合全部为 0。

3. **碰撞精度**：实测首次碰撞的接触点半径与球心半径，和画出来的环沿对拍。 **旋转体**要在环的**局部坐标系**里比（`get_normal()` 是世界系），
   并从缺口对面的径向外侧反复注入取样。实测见上方「旋转环的碰撞精度」表。

4. **「逃出却没碎」专项**（这一条专治用户报的那个 bug）：
   - 确定性入射扫描：单环 + 单球，瞄准角覆盖缺口两侧（−16°..71°，1° 步进），
     自转取 0 / ±1.8°/帧，共 264 次。
   - 随机自由对撞压力：缺口 20°/55°/90°/150°、自转 ±8°/帧、随机初位初速，600 次。
   - 整局连跑：挂真 `main.tscn`，固定随机种子，跑数万帧。
   - **判据**：「球心持续（≥8 帧）越过破环线而环还活着」必须为 0；
     另外统计「碎环时球心角度落在缺口外」= 从实心处穿模的次数，也必须为 0。
     > 判据要取**持续**多帧，不能只看单帧最大值 —— 曾经因为收尾那一帧的采样
     > 得到一个假阳性（球心 `74.545` vs 破环线 `73.267`），换成持续判据后为 0。

5. **玩法闭环**：跑数千帧观察 `state` 转换与 `wins` 计数。用 `seed()` 固定随机布局
   让结果可复现，实测（`seed(20260214)`，4 环 / gap 90）：
   
   ```
   状态转换: ["1:PLAY","423:SETTLE","498:PLAY","563:SETTLE","695:PLAY","890:SETTLE",
           "1022:PLAY","1423:SETTLE","1555:PLAY","2439:SETTLE","2572:PLAY","2965:SETTLE"]
   wins=6
   ```
   
   每次 `SETTLE` 持续约 130 帧（庆祝动画 ~2.2s）后自动开下一局。

6. **UI 结构**：`HSlider` ×3（`Rings [1,15] step1` / `Gravity [0.05,0.8] step0.05` / `Gap Size [20,150] step5`）、`Button` ×47、`Label` ×11、`Panel` ×1、 `VBoxContainer` ×3、`HBoxContainer` ×5、`GridContainer` ×2；
   滑块 `value_changed` 驱动配置（实测设 999 被钳到 max=15，设 3 得到 cfg=3）。

7. **必须用真实渲染器跑一遍整局**。headless 有两个坑会让它**掩盖真 bug**：
   视口只有 64×64（相机/出界判定区全不对），而且它不渲染 → 不出画面问题。
   实测第 9 条那个「flushing queries」就是**只有真实渲染器才暴露**的。
   顺带还要查一次节点的形状注册情况（编辑器警告的等价判据）：
   
   ```
   SHAPES SolidBody     owners=4 shapes=48 空多边形=0 子节点=4
   SHAPES EscapeDetector owners=4 shapes=48 空多边形=0 子节点=4
   ```

8. **相机映射**：**必须用真实渲染器**，读 `Camera2D.get_canvas_transform()` 换算世界中心与内容包围盒。

> ⚠️ 真渲染器跑长局要给 `--quit-after` 留**够但不要过分**的值：给太大（例如
> 200000）会在 harness 跑完之后继续空转渲染几十分钟，看起来像卡死。

> ⚠️ 临时 harness 记得删干净，包括 Godot 生成的 `_xxx.gd.uid`。
> 收尾用 `Get-ChildItem godot-ballgame -Filter '_*'` 确认没有残留，
> 并确认 `project.godot` 里没有 `[autoload]`。曾经忘记清理，残留的 autoload
> 每次启动都把配置改成 `rings_count=1 / gap_size=150`，表现为「之前正常的显示全坏了」。

> ⚠️ `print()` 输出在 `get_tree().quit()` 时可能被截断（缓冲未刷新），
> 排查时曾因此看到**乱序/缺失的日志并得出错误结论**。让场景跑满固定帧数再退出，
> 不要中途 `quit()`。

> ⚠️ 想让 headless 跑得快（不按真实时间等物理步），加 `--fixed-fps 60`，
> 否则物理步按真实时钟推进，几万帧要跑几分钟。

---

## 下一步（建议）

1. ✔ **竖屏 9:16 已改完**（1080×1920，见「竖屏版式」）—— 顺带修掉了旧版
   「盘面只占画面宽 33% 且偏心 105px」的两个取景 bug。
2. 手感增强（按调研总报告 T5/T6）：碰撞瞬间 squash & stretch、震屏、顿帧。
3. 音效**补素材** —— 机制（`AudioFX` + `AudioStreamPolyphonic`）和代码路径都已就绪，
   只差把音频文件路径填进 `Config.AUDIO`；现在跑起来会打
   `[AudioFX] xxx：没有可用音频，该音效保持静默`。
4. ✔ 离线渲染已接入（见「离线渲染」）→ 下一步是 CapCut 卡点与竖屏导出
   （总报告 T12/T22/T23）。

> ✔ **成片可复现**：同一个 `Config.MOVIE_SEED` 连续两次渲染，整文件 SHA256 完全相同
> （实测 3179 帧、1080×1920、60fps）。
> 关键一步是给 GPU 粒子固定随机种子 —— `GPUParticles2D` 的随机源**独立于**
> 游戏的 `seed()`，官方提供了 `use_fixed_seed` / `seed`，文档原话就点名了
> Movie Maker mode；另外一次性发射器必须 `restart(true)` 才不会重抽种子。
> 排查过程见 `.dsh/skills/godot-project/examples.md` 案例 27。
