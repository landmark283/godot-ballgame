extends Node
## 音效：全部由 Godot 官方音频节点实现。
##
## 层次（见 audio_fx.tscn）：
##   Player  AudioStreamPlayer —— 唯一播放器，stream 是官方的 `AudioStreamPolyphonic`
##
## ## 为什么是「一个 Player + AudioStreamPolyphonic」
##
## 一次撞碎多个环时会有好几个撞击音在同一帧发生。若用一个普通
## `AudioStreamPlayer`，后一次 `play()` 会把前一次**截断**，只听到最后一个；
## 官方给的解法就是 `AudioStreamPolyphonic`：一个播放器里并发播任意多条流，
## 并且在 `play_stream()` 时**逐条**指定音量与音高（不会互相踩）。
##
##     var pb := $Player.get_stream_playback() as AudioStreamPlaybackPolyphonic
##     var id := pb.play_stream(stream, 0.0, volume_db, pitch_scale)
##
## ## 为什么不用 `AudioStreamRandomizer`
##
## 它是按**资源**随机（样本池 + 音高/音量抖动），但 `play_stream()` 播放的是
## **一条普通的 AudioStream**，把 Randomizer 塞进去它只会当作一层包装，
## 我们自己算好的「撞击力度 → 音高/音量」就传不进去了。
## 所以这里改为在脚本里随机选样本（`Sound.pick()`）并主动传参 —— 既拿到
## 逐次变化，又保留力度映射。
##
## ## 参数来源与优先级（高 → 低）
##
## ```
## Config.AUDIO 里每个音效节的 "streams"（音频文件路径表，按概率均等随机选一条）
##   > audio_fx.tscn 里保存的值
## ```
##
## 出厂状态**没有任何音频文件**（`Config.AUDIO` 的 `streams` 全为空数组），
## 此时每个音效都保持静默并**只警告一次**，不影响画面渲染 —— 拿到素材后往
## `assets/audio/cc0/` 里放文件、把路径填进 `Config.AUDIO` 即可开声。
##
## ⚠️ 录制时引擎写出的 WAV（`--write-movie *.png` 会附赠一条同步音轨）
##    是**输出**，不是输入 —— 别把它当成素材又读回来。
##
## ## 已知无害问题：退出时一条泄漏警告
##
## 只要场景里有本节点（`AudioStreamPlayer` 播过 `AudioStreamPolyphonic`），
## 引擎在关闭时会打一条：
##
##     WARNING: ObjectDB instances leaked at exit
##     Leaked instance: AudioStreamPlaybackPolyphonic - Reference count: 1
##
## 已做的排查与结论（都是实测对照）：
##
## - 把本节点从 `main.tscn` 里去掉，**同一条命令就没有该警告** → 确实是它；
## - 对照组「普通 `AudioStreamWAV` + autoplay」下，报出的仍是**同一个对象 ID**
##   —— 说明报的就是本节点那个播放实例，不是探针或别处；
## - 试过在 `_exit_tree()` 里 `stop()` 并把 `stream` 置为 `null`，**不解决问题**；
## - 只有 `autoplay`、**从未调用** `play_stream()` 时同样会泄漏，
##   所以与「播了几条 voice」无关。
##
## **根因未定位到引擎源码级**（本机没有 Godot 源码可查），但从上面几条可确定
## 是「`AudioStreamPlayer` 持有 `AudioStreamPolyphonic` 播放实例」这件事本身。
##
## **影响：无。** 它发生在进程退出阶段，游戏过程中一切正常，出片产物不受影响
## （实测整局录制 3179 帧 / 1080×1920 / 60fps，退出码 0）。不去绕它。

## 一个时间窗内最多并发几条音效。撞击密度很高时，超出的直接丢弃：
## 听觉上分辨不出，却避免了削顶与无谓的 voice 占用。
const MAX_VOICES_PER_WINDOW := 4

## 并发计数的滚动窗口（微秒）。用一个**时间窗**而不是「每帧清零」——
## ⚠️ 改用时间窗的原因（实测踩到）：一帧内的 N 次撞击**全部发生在 `_process`
##    清零之后**，计数在帧内根本涨不起来，`_process` 一来又归零，
##    于是「每帧上限」形同虚设（实测连发 10 次后计数仍是 0，一次都没被丢）。
##    撞击本来就是同一帧里成簇发生的，按帧限流恰好错开了要限的那一段。
const VOICE_WINDOW_USEC := 50_000

var _window_start_usec := 0
var _voices_in_window := 0


## 一个音效节：样本池 + 该节的配置字典。
##
## ## 「按强度分档」的样本池
##
## `Config.AUDIO` 里列出的文件按**文件名里的强度词**自动分档：
##
##     impactPlate_light_003.wav   -> "light"
##     impactPlate_medium_001.wav  -> "medium"
##     impactPlate_heavy_004.wav   -> "heavy"
##
## 这不是为 Kenney 写死的：那套命名在免费音效库里非常常见，
## 而它恰好把「撞击力度」这一维**免费**给了我们 ——
## Kenney 的 light/medium/heavy **本来就是按力度录制的真实音频**，
## 比拿一个样本去变调要自然得多（变调会同时改变音色，听上去像塑料）。
##
## 于是分工是：
##   * **选哪一族**（`streams` 指向的目录）→ 你决定，代表材料（金属/玻璃…）
##   * **选哪一档**（本机制）→ 撞击速度决定
##   * 音高/音量微调 → 只做小幅修饰，不承担「力度」这件事
##
## 档名用 `_intensity_of()` 从路径里找；找不到档名的文件归入 `"any"`，
## 于是「没分档的样本池」也能照常工作（所有档都能挑到它）。
class Sound:
	## 档名 → 该档的样本池。
	var tiers := {}
	## 所有样本（`tiers` 的并集），用于给 `has_streams()` 之类的判断。
	var all: Array[AudioStream] = []
	var name := ""
	var cfg := {}

	func _init(p_name: String, p_cfg: Dictionary) -> void:
		name = p_name
		cfg = p_cfg

	func has_streams() -> bool:
		return not all.is_empty()

	## 某一档的池子。该档没有样本时回落到「全部样本」——
	## 这样「只放了一条、没写强度词」的素材也能正常工作，不会静音。
	func tier_pool(tier: String) -> Array:
		var p: Array = tiers.get(tier, [])
		return p if not p.is_empty() else all

	## 从某一档里等概率挑一条。
	func pick(tier := "") -> AudioStream:
		var pool: Array = tier_pool(tier) if tier != "" else all
		if pool.is_empty():
			return null
		if pool.size() == 1:
			return pool[0]
		return pool[randi() % pool.size()]

	## 取一个 float 参数：本节的配置 > `fallback`。
	## 走 `float()` 转换，免得 Variant 直接进 `lerpf()` 之类的强类型参数。
	func num(key: String, fallback: float) -> float:
		return float(cfg.get(key, fallback))


var bounce: Sound
var ring_break: Sound
var celebration: Sound
var ui_click: Sound

var _sounds: Array[Sound] = []

@onready var _player: AudioStreamPlayer = $Player


func _ready() -> void:
	bounce = Sound.new("bounce", Config.AUDIO.get("bounce", {}))
	ring_break = Sound.new("ring_break", Config.AUDIO.get("ring_break", {}))
	celebration = Sound.new("celebrate", Config.AUDIO.get("celebrate", {}))
	ui_click = Sound.new("ui_click", Config.AUDIO.get("ui_click", {}))
	_sounds = [bounce, ring_break, celebration, ui_click]
	for s in _sounds:
		_load_pool(s)
	# ⚠️ **不在这里取 playback 句柄。** `get_stream_playback()` 只在 player
	#    **处于播放状态**时才有效，空闲时返回 null 并报
	#    "Player is inactive. Call play() before requesting get_stream_playback()."
	#    （实测确认）。而 `autoplay` 也要**等一帧**才真正 play。
	#    所以句柄一律在 `_play()` 里现取 —— 那时播放状态是确定的。


## 把 `Config.AUDIO` 里列出的文件读成 AudioStream，并按文件名里的强度词分档。
##
## ⚠️ 单个文件缺失只警告、不中断 —— 一个音效没素材不该拖垮整条出片管线。
func _load_pool(s: Sound) -> void:
	var paths: PackedStringArray = s.cfg.get("streams", PackedStringArray())
	for p in paths:
		if not ResourceLoader.exists(p):
			push_warning("[AudioFX] %s：音频文件不存在，已跳过：%s" % [s.name, p])
			continue
		var st := load(p)
		if not (st is AudioStream):
			push_warning("[AudioFX] %s：不是音频资源，已跳过：%s" % [s.name, p])
			continue
		s.all.append(st)
		var tier := _intensity_of(p)
		if not s.tiers.has(tier):
			s.tiers[tier] = [] as Array[AudioStream]
		(s.tiers[tier] as Array[AudioStream]).append(st)
	if not s.has_streams():
		push_warning("[AudioFX] %s：没有可用音频，该音效保持静默（把文件路径填进 Config.AUDIO）。"
				% s.name)
	else:
		# 一条日志说清「分了哪几档、各几条」——调音时最需要知道的就是这个。
		var parts: PackedStringArray = []
		for k in ["light", "medium", "heavy", "any"]:
			if s.tiers.has(k):
				parts.append("%s×%d" % [k, (s.tiers[k] as Array).size()])
		print("[AudioFX] %s：%d 条样本（%s）" % [s.name, s.all.size(), ", ".join(parts)])


## 从路径里认强度档名。认不出就返回 `"any"`。
##
## ⚠️ 先查 heavy/light 再查 medium：`impactSoft_heavy` 里同时含 "soft"，
##    这里只按明确的三档词判断，所以顺序上把长的、唯一的先判掉。
static func _intensity_of(path: String) -> String:
	var f := path.get_file().to_lower()
	for k in ["heavy", "light", "medium"]:
		if f.contains(k):
			return k
	return "any"


# ------------------------------------------------------------------ 游戏调用

## 球撞到圆环实心处。
##
## `speed` 是撞击前的速度（**世界单位 / 物理帧**，与 `Config.BALL_MIN_SPEED` 同尺度）。
##
## **档位由速度决定，而不是靠变调**：速度按 `Config.BOUNCE_TIERS` 的门限分成
## light / medium / heavy，然后从**对应档**的样本池里挑 —— Kenney 那三档是
## 按力度真实录制的，比拿一个样本变调自然得多。
## 音高/音量只做**小幅**修饰（`pitch_soft/hard` 故意收得很窄），
## 因为「力度」这件事已经由档位承担了。
func sfx_bounce(speed: float) -> void:
	if bounce == null:
		return
	var tier := _tier_for_speed(speed)
	# 档内位置：0 = 刚跨进本档，1 = 本档上限。用来做音量/音高的小幅渐变。
	# ⚠️ 必须 `float()` 显式转换：从 Dictionary 取出来的是 Variant，
	#    直接赋值给 `var lo := ...` 会报「Cannot infer the type」。
	var bounds: Array = Config.BOUNCE_TIERS.get(tier, [0.0, 1.0])
	var lo := float(bounds[0])
	var hi := float(bounds[1])
	# heavy 档上界是 INF，换成本常量，否则 `inverse_lerp(x, INF, x)` 恒为 0。
	if is_inf(hi):
		hi = HEAVY_TIER_CEIL
	var t := clampf(inverse_lerp(lo, hi, speed), 0.0, 1.0)
	_play(bounce,
			lerpf(bounce.num("volume_db_soft", -13.0),
					bounce.num("volume_db_hard", -3.0), t),
			lerpf(bounce.num("pitch_soft", 0.96),
					bounce.num("pitch_hard", 1.12), t),
			tier)


## 分档用的最高档「可见上沿」。
##
## `Config.BOUNCE_TIERS.heavy` 的上界是 `INF`（捕获一切更快的球），
## 但 `INF` 拿去做档内渐变会让 `inverse_lerp` 恒等于 0 —— heavy 档就永远
## 拿不到音量/音高的档内渐变了。这里用一个**实际会出现的速度上限**代替：
## 实测球速很少超过 10（开局 3~6，撞几次到 8 上下），取 10 足够。
## ⚠️ 它不是分档门限（门限在 `Config.BOUNCE_TIERS`），只影响渐变斜率。
const HEAVY_TIER_CEIL := 10.0


## 速度落在哪一档。门限见 `Config.BOUNCE_TIERS`。
func _tier_for_speed(speed: float) -> String:
	# 从低到高判，第一个「速度 < 上界」的档就是它。
	for tier in ["light", "medium", "heavy"]:
		var bounds: Array = Config.BOUNCE_TIERS.get(tier, [])
		if bounds.size() == 2 and speed < float(bounds[1]):
			return tier
	return "heavy"


## 球从缺口逃出、圆环碎裂。
func sfx_ring_break() -> void:
	if ring_break == null:
		return
	# 碎环音刻意不随速度大幅变化：它是「事件音」，每次都不一样反而显得散。
	_play(ring_break,
			ring_break.num("volume_db", -2.0),
			ring_break.num("pitch", 1.0))


## 通关结算。
func sfx_celebration() -> void:
	if celebration == null:
		return
	_play(celebration,
			celebration.num("volume_db", -3.0),
			celebration.num("pitch", 1.0))


## UI 按钮点击。
func sfx_ui_click() -> void:
	if ui_click == null:
		return
	_play(ui_click,
			ui_click.num("volume_db", -8.0),
			ui_click.num("pitch", 1.0))


# ------------------------------------------------------------------ 内部

func _play(s: Sound, volume_db: float, pitch_scale: float, tier := "") -> void:
	if not s.has_streams() or _player == null:
		return
	# 滚动时间窗内的并发预算，超了直接丢（听不出来，但能挡住削顶）。
	var now := Time.get_ticks_usec()
	if now - _window_start_usec >= VOICE_WINDOW_USEC:
		_window_start_usec = now
		_voices_in_window = 0
	if _voices_in_window >= MAX_VOICES_PER_WINDOW:
		return
	# 让 player 处于播放状态 —— `get_stream_playback()` 的前提条件（见 `_ready()`）。
	# `autoplay` 已经在场景里打开，所以正常情况下这里只是兜底，
	# 且**首次调用发生在 `_ready()` 之后若干帧**，播放状态早就确定了。
	if not _player.playing:
		_player.play()
	# 用 `as` 而不是 `is`：player 万一没激活时它会静默给 null，
	# 不像 `is` 那样在引擎层先刷一条 ERROR。
	var pb := _player.get_stream_playback() as AudioStreamPlaybackPolyphonic
	if pb == null:
		return
	_voices_in_window += 1
	# 再叠一层小抖动：即使同一帧响两次，两次也不会完全一样。
	var jitter := s.num("pitch_jitter", 0.06)
	var pitch := pitch_scale * randf_range(1.0 - jitter, 1.0 + jitter)
	var stream := s.pick(tier)
	if stream == null:
		return
	pb.play_stream(stream, 0.0, volume_db, maxf(0.01, pitch))
