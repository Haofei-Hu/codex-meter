修复 Windows / Linux 桌面卡片的拖动区域和内容裁切问题。

- 拖动标题或卡片内容可移动位置；刷新按钮、设置按钮和右下角缩放手柄保持可点击。
- Plus 的双额度卡片和工作进度较多时，按当前屏幕可用空间自动适配；不会只缩短窗口而裁掉内容。
- 内容超出可读大小时，中间区域可滚动；标题、刷新按钮和右下角手柄保持可见。
- 切换显示器、系统缩放比例或分辨率后重新适配，并保留设置中的缩放偏好。
- 自动刷新不再重复设置相同窗口位置和尺寸，移动窗口期间暂缓尺寸调整。

### 下载与升级

- **Windows 10/11 x64**：`windows-x64-setup.exe` 安装版，或 `windows-x64-portable.exe` 免安装版。
- **Linux x64**：`linux-x86_64.AppImage` 或 `linux-amd64.deb`。
- **macOS 13+**：`universal.dmg` / ZIP，继续使用原生 Swift 版；本次没有修改 Mac 界面。

先退出旧版 Codex Meter，再安装或运行 1.5.1。保留原有设置，无需重新登录 Codex。首次使用仍需在本机安装并登录 Codex CLI。

包含 Plus / Pro、短屏和高 DPI 工作区、超长内容、显示器变化的回归测试；Windows 额外检查实际系统拖动命中区域与按钮命中区域。

Linux 的窗口控制取决于桌面环境，Wayland 可能限制程序定位。Windows/macOS 下载包尚未正式签名/公证，请从本仓库下载，并核对 `SHA256SUMS.txt`。

MIT · Independent project, not affiliated with OpenAI.
