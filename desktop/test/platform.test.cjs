'use strict';
const test = require('node:test'), assert = require('node:assert/strict');
const fs = require('node:fs'), os = require('node:os'), path = require('node:path');
const { cliLaunch, hasHost, authStamp } = require('../src/platform.cjs');
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
