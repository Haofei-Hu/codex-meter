Mac 桌面卡片拖动修复，针对 Plus 用户反馈双额度卡片仍无法移动的问题。

- 拖动由窗口直接处理鼠标按下、移动和释放，不再依赖 SwiftUI 覆盖层和系统背景拖动。
- 从标题、额度圆圈、文字或空白处均可拖动；设置、刷新、滚动条和右下角缩放手柄保留独立操作。
- 卡片使用标准窗口层级，并显示在普通应用后方，避免桌面图标层影响鼠标事件；拖动期间暂停自动布局，释放后保存位置并适配屏幕。
- 使用与正式应用相同的窗口配置，覆盖 Plus 双额度 / Pro、75% / 100% / 160% 缩放、短屏滚动布局、窗口实际位移和控件排除测试。

推荐下载 `CodexMeter-1.5.1.4-universal.pkg`，安装时自动停止并替换旧版，保留设置和登录。支持 macOS 13+，Apple 芯片和 Intel；DMG / ZIP 为手动替换方式。无需修改 Plus 账号或重新登录。

安装包附 SHA-256 校验文件，尚未正式签名或公证。Windows 继续使用 [1.5.2](https://github.com/Haofei-Hu/codex-meter/releases/tag/v1.5.2)，Linux 继续使用 [1.5.1](https://github.com/Haofei-Hu/codex-meter/releases/tag/v1.5.1)。MIT · Independent project, not affiliated with OpenAI.
