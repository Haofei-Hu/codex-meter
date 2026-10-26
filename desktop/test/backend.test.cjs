'use strict';
const test = require('node:test'), assert = require('node:assert/strict');
const fs = require('node:fs'), os = require('node:os'), path = require('node:path');
const { setTimeout: delay } = require('node:timers/promises');
const { Backend } = require('../src/backend.cjs');
async function until(predicate, timeout = 7000) { const end = Date.now() + timeout; while (!predicate()) { if (Date.now() > end) throw new Error('Test condition timed out'); await delay(20); } }
function fixture(t, options = {}) {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'meter-backend-test-'));
  fs.writeFileSync(path.join(home, 'auth.json'), 'test-marker');
  const state = data => fs.writeFileSync(path.join(home, 'account-state.json'), JSON.stringify(data));
  state({ email: 'first@example.test', plan: 'plus', used: 35, weeklyUsed: 13 });
  const backend = new Backend({ codexHome: home, detectHost: async () => true, launch: { command: process.execPath, args: [path.join(__dirname, 'mock-codex.cjs'), home] }, ...options });
  t.after(async () => { backend.stop(); await delay(80); fs.rmSync(home, { recursive: true, force: true }); });
  const methods = () => fs.existsSync(path.join(home, 'rpc-log.jsonl')) ? fs.readFileSync(path.join(home, 'rpc-log.jsonl'), 'utf8').trim().split('\n').map(x => JSON.parse(x).method) : [];
  return { home, backend, state, methods };
}
test('quota refresh reuses account; auth change clears old rows and logout stops quota polling', async t => {
  const { home, backend, state, methods } = fixture(t); backend.start();
  await until(() => backend.state.phase === 'ready');
  assert.deepEqual(backend.state.rows.map(x => x.remaining), [65, 87]);
  await backend.refresh();
  assert.equal(methods().filter(x => x === 'account/read').length, 1);
  state({ email: 'second@example.test', plan: 'plus', used: 15, weeklyUsed: 50 });
  fs.writeFileSync(path.join(home, 'auth.json'), 'changed-auth-marker'); backend.checkLoginChange();
  assert.equal(backend.state.account, null); assert.deepEqual(backend.state.rows, []);
  await until(() => backend.state.phase === 'ready');
  assert.equal(backend.state.account.email, 'second@example.test'); assert.deepEqual(backend.state.rows.map(x => x.remaining), [85, 50]);
  fs.unlinkSync(path.join(home, 'auth.json')); backend.checkLoginChange();
  assert.equal(backend.state.phase, 'waiting'); assert.equal(backend.state.account, null); assert.deepEqual(backend.state.rows, []);
  const count = methods().length; backend.tick(); await backend.refresh(); await delay(120);
  assert.equal(methods().length, count);
});
test('an older response cannot overwrite a newly selected account', async t => {
  const { home, backend, state } = fixture(t); backend.start(); await until(() => backend.state.phase === 'ready');
  state({ email: 'first@example.test', plan: 'plus', used: 99, weeklyUsed: 99, delay: 500 });
  const pending = backend.refresh(); await delay(60);
  state({ email: 'new@example.test', plan: 'plus', used: 10, weeklyUsed: 20 });
  fs.writeFileSync(path.join(home, 'auth.json'), 'next-auth-marker'); backend.checkLoginChange();
  await until(() => backend.state.phase === 'ready'); await pending; await delay(550);
  assert.equal(backend.state.account.email, 'new@example.test'); assert.deepEqual(backend.state.rows.map(x => x.remaining), [90, 80]);
});
test('host exit pauses queries, startup resumes, missing Plus window stays unknown', async t => {
  let running = true; const { backend, state, methods } = fixture(t, { detectHost: async () => running });
  state({ email: 'plus@example.test', plan: 'plus', used: 10 }); backend.start(); await until(() => backend.state.phase === 'ready');
  assert.deepEqual(backend.state.rows.map(x => x.remaining), [90, null]);
  running = false; await backend.inspectHost(); assert.equal(backend.state.phase, 'paused');
  const count = methods().length; await backend.refresh(); assert.equal(methods().length, count);
  running = true; await backend.inspectHost(); await until(() => backend.state.phase === 'ready');
  assert.equal(backend.state.account.email, 'plus@example.test');
});

test('runtime discovery errors do not mean logout, and recheck can recover', async t => {
  let missing=true, home;
  const f=fixture(t,{launch:undefined,resolveLaunch:async()=>{
    if(missing) { const error=new Error('runtime missing'); error.code='CLI_NOT_FOUND'; throw error; }
    return {command:process.execPath,args:[path.join(__dirname,'mock-codex.cjs'),home]};
  }}); home=f.home; f.backend.start();
  await until(()=>f.backend.state.phase==='error');
  assert.equal(f.backend.state.errorCode,'CLI_NOT_FOUND'); assert.equal(f.backend.state.account,null);
  missing=false; f.backend.reload(); await until(()=>f.backend.state.phase==='ready');
  assert.equal(f.backend.state.errorCode,null); assert.equal(f.backend.state.account.email,'first@example.test');
});
test('host exit during asynchronous runtime discovery cannot start a stale backend', async t => {
  let finish;
  const {backend,home,methods}=fixture(t,{launch:undefined,resolveLaunch:()=>new Promise(resolve=>{finish=resolve;})});
  backend.start(); await until(()=>!!finish); backend.pause('Codex closed');
  finish({command:process.execPath,args:[path.join(__dirname,'mock-codex.cjs'),home]}); await delay(120);
  assert.equal(backend.rpc,null); assert.equal(backend.state.phase,'paused'); assert.deepEqual(methods(),[]);
});
test('first login wakes the backend when the Codex home directory did not exist at startup', async t => {
  const {backend,home}=fixture(t);
  const firstHome=path.join(home,'.codex'); backend.home=firstHome; backend.authFile=path.join(firstHome,'auth.json'); backend.stamp='missing';
  backend.start(); await until(()=>backend.state.phase==='ready');
  fs.mkdirSync(firstHome); fs.writeFileSync(path.join(firstHome,'auth.json'),'new-login-marker');
  await until(()=>backend.stamp!=='missing'); await until(()=>backend.state.phase==='ready');
  assert.equal(backend.state.account.email,'first@example.test');
});
