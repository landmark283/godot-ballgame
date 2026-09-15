extends SceneTree
## 一次性工具：生成 `res://default_bus_layout.tres`（Master 上挂硬限幅器）。
##
## 为什么用脚本生成而不是手写 `.tres`：资源文件里有一堆由引擎写出的元数据，
## 手抄数字**必然出错**，而且错了不一定报错 —— 本仓库第 17 条的教训。
## 做法：用官方 API 在运行时搭出想要的总线，再让引擎自己序列化。
##
## ## 踩到的两个坑（都在本文件里修掉了，别再犯）
##
## 1. **`AudioBusLayout` 没有任何成员**（`bus_count` 是 `AudioServer` 的属性）。
##    去读 `layout.bus_count` 会抛 "Invalid access to property"。
## 2. **脚本会叠加效果器**：`--script` 启动时引擎会**先加载已有的
##    `default_bus_layout.tres`**，于是「读到的 AudioServer」上已经挂着上一次
##    写进去的限幅器，再 `add_bus_effect()` 就变成 2 个、3 个……
##    所以本脚本一进来就**先清空 Master 的效果器**，保证结果只取决于本脚本。
##
## 另外：`ceiling_db = -0.3` 这个值**会被序列化**（它是非默认值）；
## 若设成默认的 `0.0`，引擎就不写这一行 —— 所以校验必须读**引擎里的实际值**，
## 而不是去 grep 文件内容。
##
## 运行方式：
##   Godot.exe --headless --path godot-ballgame --script res://tools/make_audio_bus.gd

const OUT_PATH := "res://default_bus_layout.tres"
const CEILING_DB := -0.3


func _initialize() -> void:
	# ⚠️ 先清空，否则会在已加载的布局上不断叠加（见文件头第 2 条）。
	for i in range(AudioServer.get_bus_effect_count(0) - 1, -1, -1):
		AudioServer.remove_bus_effect(0, i)
	print("BUSLAYOUT 清空后 Master 效果器数 = %d" % AudioServer.get_bus_effect_count(0))

	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = CEILING_DB
	AudioServer.add_bus_effect(0, limiter)

	var err := ResourceSaver.save(AudioServer.generate_bus_layout(), OUT_PATH)
	if err != OK:
		print("BUSLAYOUT FAIL save err=%d" % err)
		quit(1)
		return

	# 判据取**引擎里的实际值**，不是文件里有没有那一行。
	var n := AudioServer.get_bus_effect_count(0)
	if n != 1:
		print("BUSLAYOUT FAIL Master 效果器数应为 1，实际 %d" % n)
		quit(1)
		return
	var eff := AudioServer.get_bus_effect(0, 0)
	if not (eff is AudioEffectHardLimiter):
		print("BUSLAYOUT FAIL 效果器类型不对：%s" % eff)
		quit(1)
		return
	var got := (eff as AudioEffectHardLimiter).ceiling_db
	print("BUSLAYOUT OK -> %s   Master 效果器=1 个   ceiling_db=%.2f（期望 %.2f）"
			% [OUT_PATH, got, CEILING_DB])
	if not is_equal_approx(got, CEILING_DB):
		print("BUSLAYOUT FAIL ceiling_db 不符")
		quit(1)
		return
	quit(0)
