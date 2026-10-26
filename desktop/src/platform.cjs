'use strict';
const fs = require('node:fs'), path = require('node:path'), os = require('node:os');
const { execFile } = require('node:child_process');
const { promisify } = require('node:util');
const execute = promisify(execFile);
const { windowsCandidates, installedWindowsMetadata, isConsoleExecutable } = require('./windows-discovery.cjs');
function cliLaunch(custom, { platform = process.platform, home = os.homedir(), env = process.env, node = process.execPath, runtimeDir, processes = [], packages = [] } = {}) {
  const win = platform === 'win32';
  const candidates = [...(custom ? [custom] : []), ...(env.CODEX_CLI_PATH ? [env.CODEX_CLI_PATH] : [])];
  const names = win ? ['codex.exe', 'codex.cmd', 'codex'] : ['codex'];
  const directories = [...(env.PATH || '').split(win ? ';' : ':').filter(Boolean), path.join(home, '.local', 'bin'), path.join(home, '.cargo', 'bin'), path.join(home, '.npm-global', 'bin')];
  if (win) {
    directories.push(path.join(env.APPDATA || path.join(home, 'AppData', 'Roaming'), 'npm'));
    for (const base of [env.LOCALAPPDATA, env.ProgramFiles].filter(Boolean)) {
      for (const app of ['Codex', 'ChatGPT']) for (const leaf of ['resources', 'Resources']) candidates.push(path.join(base, 'Programs', app, leaf, 'codex.exe'));
    }
  }
  if (platform === 'darwin') for (const base of [path.join(home, 'Applications'), '/Applications']) for (const app of ['ChatGPT.app', 'Codex.app']) {
    candidates.push(path.join(base, app, 'Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex'), path.join(base, app, 'Contents/Resources/codex'));
  }
  if (win) candidates.push(...windowsCandidates({ home, env, processes, packages }));
  for (const dir of directories) for (const name of names) candidates.push(path.join(dir, name));
  if (win && runtimeDir) candidates.push(...windowsCandidates({ home, env: {}, runtimeDir }).filter(x => x.startsWith(runtimeDir + path.sep)));
  for (const candidate of [...new Set(candidates)]) {
    try {
      if (!fs.statSync(candidate).isFile()) continue;
      if (/\.(cmd|bat)$/i.test(candidate)) {
        // Resolve the npm shim without invoking a shell or interpolating executable paths.
        const script = path.join(path.dirname(candidate), 'node_modules', '@openai', 'codex', 'bin', 'codex.js');
        if (fs.existsSync(script)) return { command: node, args: [script], env: { ELECTRON_RUN_AS_NODE: '1' } };
        continue;
      }
      if (win && !isConsoleExecutable(candidate)) continue;
      fs.accessSync(candidate, win ? fs.constants.F_OK : fs.constants.X_OK);
      return { command: candidate, args: [], source: runtimeDir && candidate.startsWith(runtimeDir + path.sep) ? 'bundled' : 'local' };
    } catch {}
  }
  const error = new Error(win ? '未找到可用的 Codex 运行程序；请重新安装新版 Codex Meter，或在设置中选择桌面应用内的 codex.exe。' : '未找到 Codex CLI；请安装 Codex 并登录，或选择 codex 程序。'); error.code = 'CLI_NOT_FOUND'; throw error;
}
function authStamp(file) {
  try { const s = fs.statSync(file); return `${s.ino}:${s.size}:${s.mtimeMs}`; } catch { return 'missing'; }
}
async function hostRunning() {
  try {
    if (process.platform === 'win32') {
      const { stdout } = await execute('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', 'Get-CimInstance Win32_Process | Select-Object ProcessId,ParentProcessId,Name | ConvertTo-Json -Compress'], { windowsHide: true, timeout: 8000, maxBuffer: 4e6 });
      const list = JSON.parse(stdout || '[]'); return hasHost(Array.isArray(list) ? list.map(x => ({ pid: x.ProcessId, parent: x.ParentProcessId, name: x.Name })) : []);
    }
    const { stdout } = await execute('ps', ['-eo', 'pid=,ppid=,comm='], { timeout: 5000, maxBuffer: 4e6 });
    return hasHost(stdout.split('\n').map(line => { const match = line.trim().match(/^(\d+)\s+(\d+)\s+(.+)$/); return match && { pid: +match[1], parent: +match[2], name: path.basename(match[3]) }; }).filter(Boolean));
  } catch { return null; } // Unknown must not be mistaken for a deliberate exit.
}
function hasHost(list) {
  const excluded = new Set([process.pid]);
  for (let changed = true; changed;) { changed = false; for (const p of list) if (excluded.has(p.parent) && !excluded.has(p.pid)) { excluded.add(p.pid); changed = true; } }
  return list.some(p => !excluded.has(p.pid) && /^(codex|chatgpt)(?:[ ._-].*)?(?:\.exe)?$/i.test(p.name));
}
function autostartExecutable(platform, env, fallback) {
  // Portable launchers unpack Electron into a temporary directory. Persist the outer launcher.
  if (platform === 'win32') return env.PORTABLE_EXECUTABLE_FILE || fallback;
  if (platform === 'linux') return env.APPIMAGE || fallback;
  return fallback;
}
async function resolveCliLaunch(custom, options = {}) {
  const platform = options.platform || process.platform;
  const metadata = platform === 'win32' ? await (options.discoverWindows || installedWindowsMetadata)() : {};
  return cliLaunch(custom, { ...metadata, ...options, platform });
}
module.exports = { cliLaunch, resolveCliLaunch, authStamp, hostRunning, hasHost, autostartExecutable };
