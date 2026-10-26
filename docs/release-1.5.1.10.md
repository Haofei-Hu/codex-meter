接入 macOS 26 原生液态玻璃，并扩大外观范围。

- macOS 26+ 使用真正的 `NSGlassEffectView`，高光、折射和边缘光感由系统渲染。默认使用标准玻璃，透明度超过 100% 切换为原生通透玻璃；更早系统保留兼容磨砂。
- 保留独立的背景模糊底层，卡片移动到文字或图标上方时继续模糊后方内容；磨砂遮挡放在原生玻璃内部，保留系统高光。
- 透明度和磨砂强度均为 0–200%。透明度 100–200% 逐渐减少较厚的材质，磨砂 200% 为实色遮挡。文字和按钮保持清晰，原有参数保留。
- 桌面和弹窗使用同一套背景，去掉额外叠加的系统底色和窗口阴影，继续使用原生定位、弹出与关闭动画。
- 保留浅色／深色底色、同步参数、单独还原和自动保存；设置会标明“液态玻璃”或“兼容磨砂”。

推荐安装 `CodexMeter-1.5.1.10-universal.pkg` 自动替换旧版，保留设置与登录。支持 macOS 13+、Apple 芯片与 Intel；DMG / ZIP 为手动替换。

Windows 继续使用 [1.5.2](https://github.com/Haofei-Hu/codex-meter/releases/tag/v1.5.2)，Linux 继续使用 [1.5.1](https://github.com/Haofei-Hu/codex-meter/releases/tag/v1.5.1)。MIT · Independent project, not affiliated with OpenAI.
