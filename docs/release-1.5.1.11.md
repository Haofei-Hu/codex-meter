调整 Mac 小组件外观与真实透明范围。

- 新增“应用苹果小组件外观”预设，统一桌面和弹窗的透明磨砂底、浅色文字、大圆角与细亮边；不使用固定蓝色或蓝灰色，颜色来自后面的壁纸或窗口。
- 透明度、磨砂强度均扩展为 0–300%。透明度 200–300% 会逐步减少额外的 HUD 材质，300% 透明度、0 磨砂只保留原生通透玻璃。
- 提高磨砂会使用原生自适应模糊玻璃，并增强背景模糊和中性遮挡。0 磨砂的通透端会保留更多背景细节。
- 修复深色只传给模糊层、未传给原生玻璃层的问题，确保文字与背景的外观一致。
- 外观可继续微调、同步、单独还原，并在重启后保留。旧版 macOS 使用系统兼容磨砂，其透明效果受系统材质支持限制。

推荐安装 `CodexMeter-1.5.1.11-universal.pkg` 自动替换旧版，保留设置与登录。支持 macOS 13+、Apple 芯片与 Intel；DMG / ZIP 为手动替换。

Windows 继续使用 [1.5.2](https://github.com/Haofei-Hu/codex-meter/releases/tag/v1.5.2)，Linux 继续使用 [1.5.1](https://github.com/Haofei-Hu/codex-meter/releases/tag/v1.5.1)。MIT · Independent project, not affiliated with OpenAI.
