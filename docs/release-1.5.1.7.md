统一 Mac 原生材质与弹出动画。

- 去掉上一版自加的黑色衬底、渐变高光、边框染色和固定深色外观；桌面卡片采用系统弹窗材质，文字与控件跟随系统浅色／深色模式。
- 状态栏展开面板改为原生 NSPopover，由 macOS 负责背景、定位、弹出与收起动画；设置面板也采用原生弹窗，不再叠加第二层玻璃。
- 内容更新复用现有弹窗控制器，避免同步时反复播放整个面板的切换动画；保留独立桌面位置、四边拖动与右下角缩放。
- 透明材质会随背后的壁纸或窗口变化，系统负责最终颜色和辅助功能效果。

推荐安装 `CodexMeter-1.5.1.7-universal.pkg` 自动替换旧版，保留设置与登录。支持 macOS 13+、Apple 芯片与 Intel；DMG / ZIP 为手动替换。安装包尚未正式签名或公证，附 SHA-256 校验文件。

Windows 继续使用 [1.5.2](https://github.com/Haofei-Hu/codex-meter/releases/tag/v1.5.2)，Linux 继续使用 [1.5.1](https://github.com/Haofei-Hu/codex-meter/releases/tag/v1.5.1)。MIT · Independent project, not affiliated with OpenAI.
