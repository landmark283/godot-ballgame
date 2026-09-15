# 音频素材来源与许可

## 结论：全部 CC0，可商用、可修改、**无需署名**

下面两包都来自 **Kenney**（<https://kenney.nl>），许可为
**Creative Commons Zero (CC0 1.0)** —— <https://creativecommons.org/publicdomain/zero/1.0/>。
随包附带的 `License.txt` 原文即写明 `License: (Creative Commons Zero, CC0)`。

CC0 意味着**不强制署名**。本文件是出于工程可追溯性而保留的记录，
不是许可要求 —— 但**建议保留**：将来要证明素材来源时，这是唯一凭据。

---

## 原始压缩包（保留在 `assets/sounds/` 下，勿删）

| 文件 | 内容 | 许可 |
| --- | --- | --- |
| `kenney_impact-sounds.zip` | Impact Sounds 1.0（2019-12-19），130 个撞击/脚步音 | CC0 |
| `kenney_sci-fi-sounds.zip` | Sci-fi Sounds，80 个科幻音效 | CC0 |

## 实际用到的文件（按用途分目录）

| 目录 | 取自 | 数量 | 对应游戏事件 |
| --- | --- | --- | --- |
| `ring_hit/` | `kenney_impact-sounds` → `impactPlate_{light,medium,heavy}_{000..004}` | 15 | 球撞到环的实心处 |
| `ring_break/` | `kenney_impact-sounds` → `impactGlass_medium_{000..004}` | 5 | 球从缺口逃出、环碎裂 |
| `celebration/` | `kenney_sci-fi-sounds` → `explosionCrunch_{000..002}` | 3 | 通关结算 |
| `ui_click/` | `kenney_sci-fi-sounds` → `laserSmall_{000..002}` | 3 | UI 按钮点击 |

路径在 `scripts/config.gd` 的 `Config.AUDIO` 里逐个列出。
**文件名里的 `light` / `medium` / `heavy` 是功能性的** ——
`scripts/audio_fx.gd` 靠它分档（撞击速度 → 选哪一档），改名会破坏这个机制。

## 格式：已从 Kenney 原包的 `.ogg` 全部转成 `.wav`

Godot 官方 Best practices 的建议是
「**WAV for short and repetitive sound effects**，Ogg Vorbis for music, speech,
and long sound effects」（`importing_audio_samples`）。这 26 条素材实测
**0.24 ~ 1.36 s、全程 44100 Hz**，全部落在「短促反复」那一侧，故转为 WAV。

用 **ffmpeg** 转换，命令只有一条（逐文件）：

```powershell
ffmpeg -i <原文件>.ogg -ac 1 -ar 44100 -c:a pcm_s16le <输出>.wav
```

| 决定 | 依据 |
| --- | --- |
| **单声道**（`-ac 1`） | 官方：「Many sound effects can generally be converted to mono as opposed to stereo」。原素材除 `celebration` 外都是立体声，转单声道**体积减半**。本工程也没有声像信息（音效走 `AudioStreamPolyphonic` 直送 Master，不做 2D/3D 声像）。 |
| **44100 Hz**（`-ar 44100`） | 与源一致，不重采样。官方：「除非运行时降速播放，否则高于 48 kHz 没有可听收益」。 |
| **PCM 无损**（`-c:a pcm_s16le`） | 播放 CPU 最低，官方说「hundreds of simultaneous voices 都没问题」。撞击密集时同帧并发 4 条，有实际意义。 |

### ⚠️ 转换之后还有一步，否则等于没转

Godot **默认把 WAV 导入成 Quite OK Audio（有损）**，`ResourceImporterWAV` 的
`compress/mode` 默认值是 `2`。所以每个 `.wav.import` 里都显式写成了：

```ini
compress/mode=0
```

**漏掉这一步，文件是 `.wav` 但内容仍是有损压缩的** —— 最容易误判为「已经无损了」。

### 校验数据（实测）

| 项 | 值 |
| --- | --- |
| 文件数 | 26（全部转换成功，ffmpeg 退出码 0） |
| 峰值范围 | **−5.7 ~ −0.6 dBFS**（未削顶，无需限幅；**故意没有归一化**） |
| 磁盘体积 | 340 KB（`.ogg`）→ **1,289 KB**（`.wav`） |
| 引擎内导入结果 | 26/26 `PCM16 / 44100 / 单声道`（探针读 `AudioStreamWAV.format` 实测） |
| `.godot/imported/*.sample` | 272 KB（QOA）→ 1,298 KB（PCM） |

> **音量刻意没动。** 归一化会和 `Config.AUDIO` 里的 `volume_db_soft/hard`
> 叠加，两处同时管音量必然失控。峰值本来就都在 −0.6 dBFS 以下，不需要压。
>
> **原 `.ogg` 已删除**，但两个 Kenney 原包 zip 仍在本目录下，随时可以
> 用上面的命令重新导出成任何格式（例如想改成 QOA 省体积，把
> `compress/mode` 改回 `2` 重导即可，不必重新转码）。

## 换素材时注意

- 保持 `_light` / `_medium` / `_heavy` 命名约定，否则会全部落进 `any` 档
  （仍能播放，但「撞击力度分级」就失效了）。
- Kenney Impact Sounds 里还有这些族，都带同样的三档，可直接替换 `ring_hit/`：
  `impactMetal_*`、`impactWood_*`、`impactPlate_*`、`impactGlass_*`、
  `impactTin_*`、`impactMining_*`、`impactSoft_*`、`impactPunch_*`、`impactBell_*`。
- 未用到的文件仍留在原压缩包里，需要时再解出来即可。
