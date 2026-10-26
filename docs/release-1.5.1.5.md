Mac 桌面卡片边缘拖动修复，针对 Plus 用户反馈只有中间部分能拖动的问题。

- 可拖动范围改为原生窗口的完整内容边界，取消对 SwiftUI 背景视图范围的依赖；上下左右可见边缘和留白都支持移动卡片。
- 设置、刷新、滚动条和右下角缩放手柄继续独立响应；透明圆角外侧和阴影不属于卡片操作区域。
- 覆盖 Plus 双额度 / Pro、75% / 100% / 160% 缩放和短屏布局的 960 个边缘位置，以及窗口实际位移、按钮排除和缩放检查。

推荐安装 `CodexMeter-1.5.1.5-universal.pkg` 自动替换旧版，保留设置和登录。支持 macOS 13+、Apple 芯片和 Intel。DMG / ZIP 为手动替换方式。安装包尚未正式签名或公证，附 SHA-256 校验文件。

Windows 继续使用 [1.5.2](https://github.com/Haofei-Hu/codex-meter/releases/tag/v1.5.2)，Linux 继续使用 [1.5.1](https://github.com/Haofei-Hu/codex-meter/releases/tag/v1.5.1)。MIT · Independent project, not affiliated with OpenAI.
