'use strict';
const { app, BrowserWindow, Tray, Menu, nativeImage, ipcMain, screen, dialog, powerMonitor } = require('electron');
const fs = require('node:fs'), path = require('node:path'), os = require('node:os');
const { Backend } = require('./backend.cjs');
const { autostartExecutable } = require('./platform.cjs');
const { clamp, menuFrame } = require('./model.cjs');
const { cardLayout, cardFrame } = require('../ui/geometry.js');
const { trayPNG } = require('./tray-icon.cjs');
const smoke = !app.isPackaged && process.argv.includes('--smoke-test');
if (smoke) app.setPath('userData', fs.mkdtempSync(path.join(os.tmpdir(), 'codex-meter-smoke-')));
app.setName('Codex Meter');
if (!app.requestSingleInstanceLock()) { app.quit(); } else {
  app.setAppUserModelId('io.github.HaofeiHu.CodexMeter');
  let widget, popup, tray, backend, prefs, prefsFile, latest, quitting = false, popupMode = 'overview', popupHeight = 560, holdingDialog = false, naturalCard = null, userMoving = false, smokeWorkArea = null;
  const icon = path.join(__dirname, '../assets/icon.png');
  const windows = () => [widget, popup].filter(win => win && !win.isDestroyed());
  const approved = event => windows().some(win => win.webContents === event.sender);
  function loadPrefs() {
    let saved = {}; try { saved = JSON.parse(fs.readFileSync(prefsFile, 'utf8')); } catch {}
    return { scale: clamp(Number(saved.scale) || 1, 0.75, 1.6), desktopVisible: saved.desktopVisible !== false, login: !!saved.login, followHost: saved.followHost !== false,
      alwaysOnTop: !!saved.alwaysOnTop, cliPath: typeof saved.cliPath === 'string' ? saved.cliPath : null,
      x: Number.isFinite(saved.x) ? saved.x : null, y: Number.isFinite(saved.y) ? saved.y : null };
  }
  function savePrefs() { fs.mkdirSync(path.dirname(prefsFile), { recursive: true }); const temp = `${prefsFile}.tmp`; fs.writeFileSync(temp, JSON.stringify(prefs, null, 2), { mode: 0o600 }); fs.renameSync(temp, prefsFile); }
  function areaFor(win) {
    const area = screen.getDisplayMatching(win.getBounds()).workArea;
    return smoke && win === widget && smokeWorkArea ? { ...area, width: Math.min(area.width, smokeWorkArea.width), height: Math.min(area.height, smokeWorkArea.height) } : area;
  }
  function snapshot(win = widget) {
    const area = areaFor(win);
    return { ...(latest || backend?.snapshot()), prefs, viewport: { width: area.width, height: area.height }, platform: process.platform, version: app.getVersion() };
  }
  function sendState() {
    for (const win of windows()) win.webContents.send('meter:state', snapshot(win));
    if (!tray || !latest) return;
    const waiting = ['waiting', 'paused'].includes(latest.phase), rows = waiting ? [] : latest.rows;
    const key = JSON.stringify([waiting, rows.map(x => [x.remaining, x.label]), latest.work.activeCount]);
    if (tray._imageKey !== key) { tray.setImage(nativeImage.createFromBuffer(trayPNG(rows, latest.work.activeCount > 0))); tray._imageKey = key; }
    const title = waiting ? 'Codex · 等待登录' : ['Codex 剩余额度', ...rows.map(x => `${x.label}：${x.remaining == null ? '未返回' : `${x.remaining}%`}`), latest.work.activeCount ? `${latest.work.activeCount} 个任务进行中` : '空闲'].join('\n');
    tray.setToolTip(title);
    if (tray._menuKey !== key + prefs.desktopVisible) {
      const menu = Menu.buildFromTemplate([
        { label: waiting ? '等待登录' : '查看额度与工作进度', click: () => showPopup('overview') },
        ...rows.map(row => ({ label: `${row.label}：${row.remaining == null ? '未返回' : `${row.remaining}%`}`, enabled: false })),
        { type: 'separator' }, { label: '显示桌面卡片', type: 'checkbox', checked: prefs.desktopVisible, click: () => setPreference('desktopVisible', !prefs.desktopVisible) },
        { label: '卡片设置', click: () => showPopup('settings') }, { label: '立即刷新', enabled: !waiting, click: () => backend.refresh() },
        { type: 'separator' }, { label: '退出 Codex Meter', click: () => app.quit() }
      ]);
      if (process.platform === 'linux') tray.setContextMenu(menu); else tray._contextMenu = menu;
      tray._menuKey = key + prefs.desktopVisible;
    }
  }
  function createWindow(mode) {
    const win = new BrowserWindow({ width: 348, height: mode === 'desktop' ? 410 : 600, show: false, frame: false, transparent: true, backgroundColor: '#00000000', icon,
      title: mode === 'desktop' ? 'Codex Meter' : 'Codex Meter · 额度面板', resizable: false, minimizable: false, maximizable: false, skipTaskbar: true, alwaysOnTop: mode !== 'desktop' || prefs.alwaysOnTop,
      webPreferences: { preload: path.join(__dirname, 'preload.cjs'), contextIsolation: true, nodeIntegration: false, sandbox: true, webSecurity: true, backgroundThrottling: false } });
    win.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
    win.webContents.on('will-navigate', event => event.preventDefault());
    win.webContents.session.setPermissionRequestHandler((_webContents, _permission, callback) => callback(false));
    win.loadFile(path.join(__dirname, '../ui/index.html'), { query: { view: mode } });
    win.webContents.on('did-finish-load', sendState);
    win.on('close', event => { if (!quitting) { event.preventDefault(); win.hide(); if (win === widget) { prefs.desktopVisible = false; savePrefs(); sendState(); } } });
    return win;
  }
  function clampWidget(size = naturalCard) {
    if (!size || !widget || widget.isDestroyed()) return;
    naturalCard = size;
    if (userMoving) return;
    const current = widget.getBounds(), area = areaFor(widget);
    const frame = cardFrame(current, cardLayout(size, prefs.scale, area), area);
    if (Object.keys(frame).some(key => frame[key] !== current[key])) widget.setBounds(frame);
  }
  function adaptDisplays() { clampWidget(); sendState(); if (popup?.isVisible()) positionPopup(); }
  function positionPopup() {
    const anchor = tray.getBounds();
    const cursor = screen.getCursorScreenPoint();
    const valid = anchor.width > 0 ? anchor : { x: cursor.x, y: cursor.y, width: 1, height: 1 };
    const display = screen.getDisplayMatching(valid);
    popup.setBounds(menuFrame(valid, { width: 348, height: popupHeight }, display.workArea));
  }
  function showPopup(mode) {
    if (popup?.isVisible() && popupMode === mode) { popup.hide(); return; }
    popupMode = mode;
    if (!popup || popup.isDestroyed()) {
      popup = createWindow(mode === 'settings' ? 'settings' : 'overview');
      popup.on('blur', () => { if (!holdingDialog) popup.hide(); });
      popup.webContents.on('did-finish-load', () => { positionPopup(); popup.show(); popup.focus(); });
    } else {
      popup.loadFile(path.join(__dirname, '../ui/index.html'), { query: { view: mode === 'settings' ? 'settings' : 'overview' } });
      popup.webContents.once('did-finish-load', () => { positionPopup(); popup.show(); popup.focus(); });
    }
    positionPopup();
    if (latest?.lastUpdate == null || Date.now() - latest.lastUpdate > 3000) backend.refresh();
  }
  function setLogin(value) {
    if (process.platform === 'linux') {
      const dir = path.join(process.env.XDG_CONFIG_HOME || path.join(os.homedir(), '.config'), 'autostart'), file = path.join(dir, 'codex-meter.desktop');
      if (value) {
        const exe = autostartExecutable(process.platform, process.env, process.execPath);
        if (/[\r\n]/.test(exe)) throw new Error('应用路径不支持换行');
        fs.mkdirSync(dir, { recursive: true });
        const quoted = exe.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/%/g, '%%');
        fs.writeFileSync(file, `[Desktop Entry]\nType=Application\nName=Codex Meter\nExec="${quoted}"\nTerminal=false\nX-GNOME-Autostart-enabled=true\n`, { mode: 0o600 });
      } else if (fs.existsSync(file)) fs.unlinkSync(file);
    } else app.setLoginItemSettings({ openAtLogin: value, path: autostartExecutable(process.platform, process.env, process.execPath) });
  }
  function setPreference(key, value) {
    if (key === 'scale') { if (!Number.isFinite(value)) throw new Error('无效的缩放值'); prefs.scale = clamp(value, 0.75, 1.6); }
    else if (['desktopVisible', 'login', 'followHost', 'alwaysOnTop'].includes(key)) {
      if (typeof value !== 'boolean') throw new Error('无效的设置');
      if (key === 'login') setLogin(value);
      prefs[key] = value;
      if (key === 'desktopVisible') value ? widget.showInactive() : widget.hide();
      if (key === 'followHost') backend.setFollowHost(value);
      if (key === 'alwaysOnTop') widget.setAlwaysOnTop(value);
    } else throw new Error('未知设置');
    savePrefs(); sendState(); return prefs;
  }
  app.on('second-instance', () => { if (widget) { prefs.desktopVisible = true; widget.show(); widget.focus(); sendState(); } });
  app.on('before-quit', () => { quitting = true; backend?.stop(); tray?.destroy(); });
  app.on('window-all-closed', () => {});
  app.whenReady().then(async () => {
    prefsFile = path.join(app.getPath('userData'), 'preferences.json'); prefs = loadPrefs();
    let options = { cliPath: prefs.cliPath, followHost: prefs.followHost };
    if (smoke) {
      const home = fs.mkdtempSync(path.join(os.tmpdir(), 'codex-meter-fixture-'));
      const fixture = path.join(__dirname, '../test/mock-codex.cjs');
      fs.writeFileSync(path.join(home, 'auth.json'), 'fixture');
      fs.writeFileSync(path.join(home, 'account-state.json'), JSON.stringify({ email: 'demo@example.test', plan: 'plus', used: 25, weeklyUsed: 60 }));
      fs.mkdirSync(path.join(home, 'sessions'), { recursive: true });
      const event = (type, payload) => JSON.stringify({ timestamp: new Date().toISOString(), type, payload }) + '\n';
      fs.writeFileSync(path.join(home, 'sessions', 'demo.jsonl'), event('session_meta', { id: 'demo' }) + event('event_msg', { type: 'task_started', turn_id: 'demo-turn' }) + event('response_item', { type: 'message', role: 'assistant', phase: 'commentary', content: [{ text: '正在验证跨平台卡片与托盘。' }] }));
      fs.writeFileSync(path.join(home, 'session_index.jsonl'), JSON.stringify({ id: 'demo', thread_name: '验证 Windows 与 Linux 版' }) + '\n');
      options = { codexHome: home, launch: { command: process.execPath, args: [fixture, home], env: { ELECTRON_RUN_AS_NODE: '1' } }, detectHost: async () => true };
    }
    backend = new Backend(options); latest = backend.snapshot();
    widget = createWindow('desktop');
    const area = screen.getPrimaryDisplay().workArea;
    widget.setPosition(prefs.x ?? area.x + area.width - 380, prefs.y ?? area.y + 24);
    widget.once('ready-to-show', () => { if (prefs.desktopVisible) widget.showInactive(); });
    let moveTimer;
    widget.on('will-move', () => { userMoving = true; });
    widget.on('moved', () => {
      clearTimeout(moveTimer);
      moveTimer = setTimeout(() => {
        if (widget.isDestroyed()) return;
        userMoving = false;
        adaptDisplays();
        const bounds = widget.getBounds(); prefs.x = bounds.x; prefs.y = bounds.y; savePrefs();
      }, 180);
    });
    for (const event of ['display-added', 'display-removed', 'display-metrics-changed']) screen.on(event, adaptDisplays);
    widget.on('blur', () => { if (!prefs.alwaysOnTop && !widget.isDestroyed()) { try { widget.moveBottom(); } catch {} } });
    tray = new Tray(nativeImage.createFromBuffer(trayPNG([]))); tray.setToolTip('Codex · 等待登录');
    tray.on('click', () => showPopup('overview')); tray.on('double-click', () => showPopup('overview'));
    tray.on('right-click', () => { if (tray._contextMenu) tray.popUpContextMenu(tray._contextMenu); });
    ipcMain.handle('meter:snapshot', event => { if (!approved(event)) throw new Error('Unknown window'); return snapshot(BrowserWindow.fromWebContents(event.sender)); });
    ipcMain.handle('meter:preference', (event, key, value) => { if (!approved(event)) throw new Error('Unknown window'); return setPreference(key, value); });
    ipcMain.handle('meter:action', async (event, action) => {
      if (!approved(event)) throw new Error('Unknown window');
      if (action === 'refresh') backend.refresh();
      else if (action === 'recheck') backend.reload();
      else if (action === 'settings') showPopup('settings');
      else if (action === 'close-popup') popup?.hide();
      else if (action === 'quit') app.quit();
      else if (action === 'select-cli') {
        holdingDialog = true;
        try { const result = await dialog.showOpenDialog({ title: '选择 Codex 可执行程序', properties: ['openFile'] }); if (!result.canceled && result.filePaths[0]) { prefs.cliPath = result.filePaths[0]; savePrefs(); backend.setCLI(prefs.cliPath); } }
        finally { holdingDialog = false; }
      } else throw new Error('未知操作');
    });
    ipcMain.on('meter:resize', (event, size) => {
      if (!approved(event) || !Number.isFinite(size?.width) || !Number.isFinite(size?.height) || size.width < 200 || size.height < 120 || size.width > 1200 || size.height > 4000) return;
      if (event.sender === widget.webContents) clampWidget(size);
      else { popupHeight = size.height; positionPopup(); }
    });
    backend.on('state', state => { latest = state; sendState(); }); backend.start();
    powerMonitor.on('suspend', () => backend.suspend()); powerMonitor.on('resume', () => backend.resume());
    if (smoke) {
      const timer = setTimeout(() => { console.error('Electron smoke test timed out'); app.exit(1); }, 40000);
      backend.on('state', async state => {
        if (state.phase !== 'ready' || state.rows.length !== 2 || state.work.state !== 'running' || widget._smoked) return;
        widget._smoked = true;
        try {
          await new Promise(resolve => setTimeout(resolve, 500));
          const text = await widget.webContents.executeJavaScript('document.body.innerText');
          if (!text.includes('5 小时额度') || !text.includes('每周额度')) throw new Error('Missing quota rows in renderer');
          if (!text.includes('验证 Windows 与 Linux 版') || !text.includes('正在验证跨平台卡片与托盘。')) throw new Error('Missing local work progress');
          const isolated = await widget.webContents.executeJavaScript('typeof require === "undefined" && typeof process === "undefined" && typeof window.meter === "object"');
          if (!isolated) throw new Error('Renderer is not isolated');
          await widget.webContents.executeJavaScript('window.meter.preference("scale", 1.25)');
          await new Promise(resolve => setTimeout(resolve, 350));
          if (Math.abs(widget.getBounds().width - 431) > 2) throw new Error('Card resize did not update native bounds');
          await widget.webContents.executeJavaScript('window.meter.preference("scale", 1)');
          await new Promise(resolve => setTimeout(resolve, 350));
          clearInterval(backend.timer);
          await require('../test/window-smoke.cjs')({ win: widget, screen, state: latest,
            updateState: value => { latest = value; sendState(); },
            setArea: value => { smokeWorkArea = value; adaptDisplays(); },
            setScale: value => setPreference('scale', value) });
          if (process.env.CODEX_METER_SCREENSHOT) { const image = await widget.webContents.capturePage(); fs.writeFileSync(process.env.CODEX_METER_SCREENSHOT, image.toPNG()); }
          clearTimeout(timer); console.log('PASS Electron smoke: isolated renderer, RPC, Plus windows, live work, tray and resizing'); app.quit();
        } catch (error) { console.error(error.message); app.exit(1); }
      });
    }
  }).catch(error => { console.error(error.message); app.exit(1); });
}
