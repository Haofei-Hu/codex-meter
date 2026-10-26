Windows 登录识别修复版，解决 Codex 已登录但 Meter 提示“未找到 Codex CLI”的问题。

- 补齐微软商店版、运行中的桌面应用和 `%LOCALAPPDATA%\OpenAI\Codex\bin` 后台程序的查找；支持中文和带空格的路径，避免误启动桌面 GUI。
- Windows 安装包内置锁定版本的官方 Codex 运行程序（0.164.0，Apache-2.0）作为备用，无需额外安装 CLI；不包含任何账号或登录凭据。
- 程序查找或连接失败时明确显示“尚未读取登录状态”，不再误报“未登录”。首次登录创建配置目录后也会自动重新识别；普通额度刷新继续复用账号，退出 Codex 后暂停更新。
- 在 Windows CI 实际连接备用运行程序，验证无独立 CLI、空登录目录和最终安装包中的运行程序；另包含账号切换、Plus 双额度、窗口拖动和缩放测试。未在反馈者电脑上验证其真实账号。

下载 `CodexMeter-1.5.2-windows-x64-setup.exe`，退出旧版 Meter 后安装即可覆盖升级，保留设置；也提供 `portable.exe` 免安装版。保持 Codex 打开并登录同一 Windows 用户的账号，需要时在 Meter 设置点“重新检测账号”。WSL 与 Windows 的登录配置目录分开。

安装包尚未正式签名，下载附 `SHA256SUMS.txt`。Mac 继续使用 [1.5.1.3](https://github.com/Haofei-Hu/codex-meter/releases/tag/v1.5.1.3)，Linux 继续使用 [1.5.1](https://github.com/Haofei-Hu/codex-meter/releases/tag/v1.5.1)。MIT · Independent project, not affiliated with OpenAI.
