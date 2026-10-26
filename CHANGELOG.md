# Changelog

## 1.5.1.3 (macOS)

- Advance the used-quota gap clockwise from twelve o'clock as the remaining quota decreases.
- Verify rendered clockwise direction at 95%, 75%, and 25%.

## 1.5.1.2 (macOS)

- Keep the full quota ring stroke inside its 94-point layout bounds to prevent scroll-view edge clipping.
- Add a rendered-pixel regression for ring overflow; retain the automatic replacement PKG installer.

## 1.5.1.1 (macOS)

- Replace implicit background dragging with native AppKit drag regions for Plus and Pro.
- Fit the desktop card to the active screen and scroll long contents while pinning controls.
- Disable hosting-view automatic window sizing and defer layout changes during native dragging.
- Add a universal PKG installer that replaces the app and moves matching older duplicates to Trash.
- Preserve preferences and Codex login; verify the new payload before removing duplicates.
- Windows and Linux remain on 1.5.1.

## 1.5.1

- Use a stable card-wide drag region on Windows/Linux, with controls excluded.
- Fit Plus dual-quota and busy-task cards to the current monitor instead of clipping the window.
- Keep the title, refresh button and resize grip visible; scroll excess content at readable sizes.
- Refit after monitor, work-area or DPI changes without resetting the preferred scale.
- Avoid redundant native frame updates and defer geometry adjustments during window movement.
- Add Plus/Pro and short-screen regressions, including real Windows caption/client hit testing.

## 1.5.0

- Windows x64 installer and portable app; Linux x64 AppImage and Debian package.
- Shared desktop card matching the native Mac layout, with Plus dual quotas and continuous colors.
- Colored system-tray progress, account switching, logout pause, direct corner resizing and autostart.
- Local public task progress, elapsed time, explicit plan steps and live tool status.
- Isolated Electron renderer, fixed IPC actions, local-only data and native executable launching.
- Native OS build jobs, account-switch tests, real-window smoke tests and release checksums.
- macOS continues to use the native Swift app.

## 1.4.0

Initial public release.

- Native macOS desktop card and menu bar quota display.
- Separate short-term and weekly quota windows for Plus.
- Account-switch detection and explicit waiting-for-login state.
- Continuous quota colors, resizable card, login-item preference.
- Local task lifecycle, elapsed time, public progress and explicit plan steps.
- Independent menu panel with screen-bound positioning and scrolling.
- Single-instance guard, deterministic icon drawing and local integration tests.
