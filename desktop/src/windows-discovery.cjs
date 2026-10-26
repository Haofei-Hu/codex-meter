'use strict';
const fs = require('node:fs'), path = require('node:path');
const { execFile } = require('node:child_process');
const { promisify } = require('node:util');
const execute = promisify(execFile);
let cache;
function directories(root) {
  try { return fs.readdirSync(root, { withFileTypes: true }).filter(x => x.isDirectory() && !x.isSymbolicLink()).slice(0, 128).map(x => path.join(root, x.name)).sort((a,b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs); } catch { return []; }
}
function isConsoleExecutable(file) {
  // Never start the Electron GUI executable as an app-server by mistake.
  let fd;
  try {
    fd = fs.openSync(file, 'r'); const dos = Buffer.alloc(64);
    if (fs.readSync(fd, dos, 0, 64, 0) !== 64 || dos.toString('ascii',0,2) !== 'MZ') return false;
    const offset = dos.readUInt32LE(60); if (offset > 1024 * 1024) return false;
    const pe = Buffer.alloc(96); if (fs.readSync(fd, pe, 0, pe.length, offset) !== pe.length || pe.readUInt32LE(0) !== 0x4550) return false;
    return pe.readUInt16LE(24 + 68) === 3; // IMAGE_SUBSYSTEM_WINDOWS_CUI
  } catch { return false; } finally { if (fd !== undefined) fs.closeSync(fd); }
}
function windowsCandidates({ home, env, processes = [], packages = [], runtimeDir } = {}) {
  const local = env.LOCALAPPDATA || path.join(home, 'AppData', 'Local');
  const roots = [];
  for (const p of processes) if (typeof p.ExecutablePath === 'string') roots.push(path.dirname(p.ExecutablePath));
  for (const p of packages) if (typeof p.InstallLocation === 'string') roots.push(p.InstallLocation, path.join(p.InstallLocation, 'app'));
  for (const base of [local, env.ProgramFiles, env['ProgramFiles(x86)']].filter(Boolean)) {
    for (const name of ['Codex','ChatGPT']) roots.push(path.join(base,'Programs',name),path.join(base,name));
  }
  const relocation = path.join(local,'OpenAI','Codex','bin');
  const candidates = directories(relocation).map(dir => path.join(dir,'codex.exe'));
  for (const p of processes) if (typeof p.ExecutablePath === 'string' && /[/\\](?:codex)\.exe$/i.test(p.ExecutablePath)) candidates.unshift(p.ExecutablePath);
  for (const root of new Set(roots)) {
    for (const relative of ['resources/codex.exe','resources/bin/codex.exe','resources/codex/codex.exe','resources/codex-cli/codex.exe','app/resources/codex.exe','resources/app.asar.unpacked/codex.exe']) candidates.push(path.join(root,...relative.split('/')));
  }
  if (runtimeDir) candidates.push(path.join(runtimeDir,'x86_64-pc-windows-msvc','bin','codex.exe'),path.join(runtimeDir,'aarch64-pc-windows-msvc','bin','codex.exe'));
  return [...new Set(candidates)];
}
async function installedWindowsMetadata() {
  if (cache && Date.now() - cache.time < 15000) return cache.value;
  const command = "$ErrorActionPreference='SilentlyContinue'; [Console]::OutputEncoding=[System.Text.Encoding]::UTF8; $p=@(Get-CimInstance Win32_Process | Where-Object { $_.Name -match '^(Codex|ChatGPT)\\.exe$' } | Select-Object ProcessId,ParentProcessId,Name,ExecutablePath); $a=@(@('OpenAI.Codex','OpenAI.ChatGPT-Desktop') | ForEach-Object { Get-AppxPackage -Name $_ } | Select-Object InstallLocation); @{processes=$p;packages=$a} | ConvertTo-Json -Compress -Depth 4";
  try {
    const { stdout } = await execute('powershell.exe',['-NoProfile','-NonInteractive','-Command',command],{ windowsHide:true,timeout:12000,maxBuffer:2e6 });
    const value = JSON.parse(stdout.replace(/^\uFEFF/,''));
    cache = { time:Date.now(), value }; return value;
  } catch { return { processes:[],packages:[] }; }
}
module.exports = { directories, isConsoleExecutable, windowsCandidates, installedWindowsMetadata };
