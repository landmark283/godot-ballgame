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

## 换素材时注意

- 保持 `_light` / `_medium` / `_heavy` 命名约定，否则会全部落进 `any` 档
  （仍能播放，但「撞击力度分级」就失效了）。
- Kenney Impact Sounds 里还有这些族，都带同样的三档，可直接替换 `ring_hit/`：
  `impactMetal_*`、`impactWood_*`、`impactPlate_*`、`impactGlass_*`、
  `impactTin_*`、`impactMining_*`、`impactSoft_*`、`impactPunch_*`、`impactBell_*`。
- 未用到的文件仍留在原压缩包里，需要时再解出来即可。
