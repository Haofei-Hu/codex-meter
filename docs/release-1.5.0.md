新增 Windows 与 Linux 版，与 Mac 保持相同的桌面卡片、双额度、渐变进度和本机任务进度。Mac 继续使用原生 Swift 版本。

### 下载

- **macOS 13+**：`universal.dmg`，Apple 芯片和 Intel 通用；也提供 ZIP。
- **Windows 10/11 x64**：`windows-x64-setup.exe` 安装版，或 `portable.exe` 免安装版。
- **Linux x64**：`linux-x86_64.AppImage`，或 Ubuntu / Debian 的 `.deb`。

首次使用请先安装 Codex CLI 并登录自己的 ChatGPT 账号；如果未自动找到程序，在设置中选择 Codex 可执行文件。支持 `CODEX_HOME`。Plus 的短时和每周额度分开显示，服务器未返回的窗口会明确标记。

Windows 使用系统托盘，Linux 使用桌面环境的托盘；颜色与进度随剩余额度变化。账号改变后清除旧数据并重新同步，退出后显示“等待登录”。右下角可拖动缩放卡片，支持登录启动和实时本机工作进度。

Linux 的托盘显示和窗口定位取决于桌面环境；GNOME 可能需要托盘扩展，Wayland 可能限制位置控制。Windows / Linux 的托盘入口为进度图标和额度提示文字。锁屏不会显示桌面卡片。

Windows 和 macOS 包目前没有付费开发者签名/公证，首次打开可能出现系统提示。请仅从本仓库下载并核对 `SHA256SUMS.txt`。

每个平台均在 GitHub Actions 对应系统构建；Windows / Linux 运行真实 Electron 窗口、RPC、Plus 双额度、本机工作进度与缩放冒烟测试。尚未覆盖所有 Linux 桌面环境的人工实机测试。

Source: MIT. Independent project, not affiliated with OpenAI. No token collection, telemetry or hosted backend.
