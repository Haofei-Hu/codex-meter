'use strict';
const test = require('node:test'), assert = require('node:assert/strict');
const fs = require('node:fs'), os = require('node:os'), path = require('node:path');
const { cliLaunch, resolveCliLaunch, hasHost, authStamp, autostartExecutable } = require('../src/platform.cjs');
test('Windows npm shim resolves a literal script path without a command shell', t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'meter path & spaces-')); t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const shim = path.join(root, 'codex.cmd'), script = path.join(root, 'node_modules', '@openai', 'codex', 'bin', 'codex.js');
  fs.mkdirSync(path.dirname(script), { recursive: true }); fs.writeFileSync(script, ''); fs.writeFileSync(shim, 'not executed');
  const launch = cliLaunch(shim, { platform: 'win32', env: { PATH: '' }, home: root, node: 'node.exe' });
  assert.equal(launch.command, 'node.exe'); assert.deepEqual(launch.args, [script]); assert.equal(launch.env.ELECTRON_RUN_AS_NODE, '1');
  assert.equal(authStamp(path.join(root, 'absent')), 'missing');
});
test('Meter and all its app-server descendants do not count as the Codex host', () => {
  const own = [{ pid: process.pid, parent: 1, name: 'Codex Meter.exe' }, { pid: 800001, parent: process.pid, name: 'node.exe' }, { pid: 800002, parent: 800001, name: 'codex.exe' }];
  assert.equal(hasHost(own), false);
  assert.equal(hasHost([...own, { pid: 800003, parent: 1, name: 'Codex.exe' }]), true);
  assert.equal(hasHost([...own, { pid: 800004, parent: 1, name: 'codex' }]), true);
});

test('portable autostart targets the persistent launcher rather than extracted temporary Electron', () => {
  assert.equal(autostartExecutable('win32', { PORTABLE_EXECUTABLE_FILE: 'C:\\Apps\\Meter.exe' }, 'C:\\Temp\\extracted.exe'), 'C:\\Apps\\Meter.exe');
  assert.equal(autostartExecutable('linux', { APPIMAGE: '/home/test/Codex Meter.AppImage' }, '/tmp/.mount_meter/codex-meter'), '/home/test/Codex Meter.AppImage');
  assert.equal(autostartExecutable('win32', {}, 'C:\\Apps\\Codex Meter.exe'), 'C:\\Apps\\Codex Meter.exe');
});

function pe(file, subsystem = 3) {
  const buffer = Buffer.alloc(160); buffer.write('MZ'); buffer.writeUInt32LE(64,60);
  buffer.writeUInt32LE(0x4550,64); buffer.writeUInt16LE(subsystem,64+24+68);
  fs.mkdirSync(path.dirname(file),{recursive:true}); fs.writeFileSync(file,buffer); return file;
}
function windowsFixture(t) {
  const home=fs.mkdtempSync(path.join(os.tmpdir(),'Meter 中文 & spaces-'));
  t.after(()=>fs.rmSync(home,{recursive:true,force:true}));
  return {home,env:{PATH:'',LOCALAPPDATA:path.join(home,'Local'),APPDATA:path.join(home,'Roaming')}};
}
test('Windows relocated desktop backend is found without an installed CLI', t => {
  const options=windowsFixture(t);
  const file=pe(path.join(options.env.LOCALAPPDATA,'OpenAI','Codex','bin','desktop-build-hash','codex.exe'));
  assert.equal(cliLaunch(null,{platform:'win32',...options}).command,file);
});
test('Windows Store package and running desktop paths locate the backend, never the GUI', async t => {
  const options=windowsFixture(t), install=path.join(options.home,'WindowsApps','OpenAI.Codex_build');
  const gui=pe(path.join(install,'app','Codex.exe'),2);
  const backend=pe(path.join(install,'app','resources','codex.exe'));
  const launch=await resolveCliLaunch(null,{platform:'win32',...options,discoverWindows:async()=>({packages:[{InstallLocation:install}],processes:[{ExecutablePath:gui}]})});
  assert.equal(launch.command,backend); assert.equal(launch.source,'local');
  fs.unlinkSync(backend);
  assert.throws(()=>cliLaunch(gui,{platform:'win32',...options,processes:[{ExecutablePath:gui}]}),e=>e.code==='CLI_NOT_FOUND');
});
test('Windows bundled runtime is the fallback and existing desktop backend takes priority', t => {
  const options=windowsFixture(t), runtimeDir=path.join(options.home,'resources','codex');
  const bundled=pe(path.join(runtimeDir,'x86_64-pc-windows-msvc','bin','codex.exe'));
  const first=cliLaunch(null,{platform:'win32',...options,runtimeDir});
  assert.equal(first.command,bundled); assert.equal(first.source,'bundled');
  const installed=pe(path.join(options.env.LOCALAPPDATA,'OpenAI','Codex','bin','hash','codex.exe'));
  assert.equal(cliLaunch(null,{platform:'win32',...options,runtimeDir}).command,installed);
});
