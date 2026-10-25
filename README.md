# Codex Meter

<img src="Assets/IconPreview.png" width="96" alt="Codex Meter icon">

macOS 桌面额度卡片与菜单栏工具，显示 Codex 剩余额度、重置时间和本机任务进度。

A native macOS desktop card and menu bar app for Codex quota and local task progress.

[下载 Mac 版 / Download](https://github.com/Haofei-Hu/codex-meter/releases/tag/v1.4.0)

## 下载与安装

1. 在 Releases 下载 `CodexMeter-1.4.0-universal.dmg`（Apple 芯片和 Intel 通用版）。
2. 打开 DMG，把 **Codex Meter.app** 拖入 **Applications**。
3. 打开应用，菜单栏会出现额度入口；桌面卡片可以拖动位置。
4. 本机需要先安装并登录 Codex / ChatGPT 桌面应用，或 Codex CLI。每位用户使用自己的账号，不需要提供 API Key。

要求 **macOS 13 Ventura 或更新版本**。本地测试环境为 Apple 芯片 Mac；Intel 二进制经过交叉编译，尚未在 Intel 实机验证。

当前下载包使用临时签名，**尚未经过 Apple Developer ID 签名和公证**。macOS 可能阻止首次打开；确认下载来自本仓库后，可以在“系统设置 → 隐私与安全性”查看对应的打开选项。也可以自行审阅源码并构建。无需关闭 Gatekeeper 或系统完整性保护。

## 功能

- 剩余额度百分比、重置日期和倒计时。
- Plus 的短时窗口与每周窗口上下排列；具体时长和比例以服务器返回为准。
- 绿色 → 橙色 → 红色连续渐变；菜单栏同步显示。
- 每 15 秒查询额度；打开面板时刷新，显示数据年龄。
- 登录变化时重新识别账号；退出后显示“等待登录”并停止额度请求。
- 桌面右下角可直接拖动缩放，也可以在设置中调节 75%–160%。
- 本机任务名称、运行/工具执行/完成/中断状态、耗时与最近公开进度，每 2 秒更新。
- 仅在任务记录含有明确计划步骤时显示步骤完成比例，不猜测任务百分比。
- 登录时启动、手动刷新、单实例保护。

## 锁屏和睡眠

目前是原生桌面窗口，**不是锁屏小组件**。锁屏界面不会显示桌面卡片或菜单栏；解锁后可继续查看。Mac 进入睡眠期间不会刷新。Codex 自己的任务能否继续由 Codex 和系统电源状态决定。

## 数据来源与隐私

- 通过本机 `codex app-server` 的 `account/read`、`account/rateLimits/read` 查询账号与额度。
- 账号查询只在启动、登录变化或手动重新检测时进行；常规刷新复用连接。
- 工作进度只读本机 Codex 的 `sessions` 和 `session_index.jsonl`。这些记录格式可能随 Codex 更新而改变。
- 不直接读取或复制登录令牌，不上传任务记录，不包含分析服务或自建后端。
- 任务名称与公开进度说明会显示在用户自己的桌面。不会展示私有推理、用户消息正文、工具参数或工具结果。
- 退出登录或退出 Codex / ChatGPT 应用后暂停更新。

额度表示 **剩余百分比 = 100 − 已用百分比**。Codex 原应用与本工具的请求时刻可能不同，持续使用时可能暂时存在差值。服务器未返回的窗口会明确标注，不能将“未返回”理解为 0% 或 100%。

## 从源码构建

需要 Xcode 15 或更新版本，或具备 Swift 5.9+ 的 Apple Command Line Tools。

```sh
./build.sh                            # 当前机器架构，输出到 build/
ARCHS="arm64 x86_64" ./build.sh        # 通用二进制
./scripts/test.sh                     # 本地自动测试，不修改真实登录
./scripts/package.sh                  # 创建 DMG、ZIP 与 SHA-256 校验文件
```

可用 `CODEX_METER_BUILD_DIR` 更改构建目录，用 `MACOSX_DEPLOYMENT_TARGET` 更改最低系统版本。

源码与测试位于 `Source/`，可复现的图标绘制代码位于 `Assets/MakeIcon.swift`。`--probe` 与 `--work-probe` 会只读当前账号/本机任务，适合手动排查。

## 说明

独立的个人开源项目，与 OpenAI 没有隶属关系。它不会调用模型来测算额度，也不能绕过或重置账号额度。MIT License。
