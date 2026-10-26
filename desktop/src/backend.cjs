'use strict';
const { EventEmitter } = require('node:events');
const fs = require('node:fs'), path = require('node:path'), os = require('node:os');
const { CodexRPC } = require('./rpc.cjs');
const { cliLaunch, authStamp, hostRunning } = require('./platform.cjs');
const { quotaRows } = require('./model.cjs');
const { WorkTracker } = require('./work.cjs');
class Backend extends EventEmitter {
  constructor(options = {}) {
    super(); this.options = options; this.home = options.codexHome || process.env.CODEX_HOME || path.join(os.homedir(), '.codex');
    this.authFile = path.join(this.home, 'auth.json'); this.stamp = authStamp(this.authFile); this.generation = 0; this.rpc = null; this.ready = false;
    this.refreshing = false; this.checking = false; this.nextLimits = 0; this.nextWork = 0; this.nextHost = 0; this.workBusy = false; this.hostBusy = false;
    this.stopped = false; this.retryCount = 0; this.partialRetries = 0; this.followHost = options.followHost !== false; this.lastHost = null;
    this.workTracker = new WorkTracker(this.home);
    this.state = { phase: 'loading', loading: false, account: null, rows: [], lastUpdate: null, nextUpdate: null, error: null, reason: null, now: Date.now(), work: { state: 'loading', activeCount: 0, tasks: [] } };
  }
  start() {
    this.stopped = false;
    try { this.watcher = fs.watch(this.home, { persistent: false }, () => {
      if (authStamp(this.authFile) === this.stamp) return;
      clearTimeout(this.authDebounce);
      this.authDebounce = setTimeout(() => this.checkLoginChange(), 300);
    }); } catch {}
    this.timer = setInterval(() => this.tick(), 1000);
    this.tick();
  }
  stop() {
    this.stopped = true; clearInterval(this.timer); clearTimeout(this.authDebounce); clearTimeout(this.retryTimer); this.watcher?.close();
    this.generation++; this.rpc?.close(); this.rpc = null;
  }
  publish() { this.state.now = Date.now(); this.state.nextUpdate = this.nextLimits; this.emit('state', this.snapshot()); }
  snapshot() { return JSON.parse(JSON.stringify(this.state)); }
  tick() {
    if (this.stopped) return;
    const now = Date.now();
    if (now >= this.nextHost && !this.hostBusy) this.inspectHost();
    if (!['waiting', 'paused'].includes(this.state.phase) && now >= this.nextLimits && !this.refreshing) this.refresh();
    if (this.state.account && !['waiting', 'paused'].includes(this.state.phase) && now >= this.nextWork && !this.workBusy) this.scanWork();
    this.publish();
  }
  async inspectHost() {
    this.nextHost = Date.now() + 5000; this.hostBusy = true;
    try {
      const running = await (this.options.detectHost || hostRunning)();
      if (this.stopped || running == null) return;
      const previous = this.lastHost; this.lastHost = running;
      if (this.followHost && !running && this.state.phase !== 'paused') this.pause('等待登录 · 请打开 Codex');
      else if (this.followHost && running && previous === false) this.reload();
    } finally { this.hostBusy = false; }
  }
  setFollowHost(value) { this.followHost = value; if (!value && this.state.phase === 'paused') this.reload(); else { this.nextHost = 0; this.tick(); } }
  checkLoginChange() {
    const stamp = authStamp(this.authFile); if (stamp === this.stamp) return false;
    this.stamp = stamp;
    if (stamp === 'missing' && this.state.account) this.logout(); else this.reload();
    return true;
  }
  resetConnection() { this.generation++; this.rpc?.close(); this.rpc = null; this.ready = false; this.refreshing = false; this.checking = false; clearTimeout(this.retryTimer); }
  clearAccount() {
    this.state.account = null; this.state.rows = []; this.state.lastUpdate = null; this.state.error = null;
    this.state.work = { state: 'paused', activeCount: 0, tasks: [] }; this.workTracker.clear();
  }
  pause(reason) {
    this.resetConnection(); this.clearAccount(); Object.assign(this.state, { phase: 'paused', loading: false, reason }); this.nextLimits = Infinity; this.publish();
  }
  suspend() { this.pause('系统睡眠，更新已暂停'); }
  resume() { if (this.checkLoginChange()) return; if (this.state.phase === 'paused') this.reload(); else { this.nextLimits = 0; this.tick(); } }
  logout() {
    this.generation++; this.rpc?.cancelPending(); this.refreshing = false; this.checking = false; clearTimeout(this.retryTimer);
    this.clearAccount(); Object.assign(this.state, { phase: 'waiting', loading: false, reason: '等待登录 · 已退出登录' }); this.nextLimits = Infinity; this.publish();
  }
  reload() {
    if (this.followHost && this.lastHost === false) { this.pause('等待登录 · 请打开 Codex'); return; }
    this.resetConnection(); this.clearAccount(); this.retryCount = 0; this.partialRetries = 0;
    Object.assign(this.state, { phase: 'loading', loading: false, reason: null }); this.nextLimits = 0; this.refresh();
  }
  setCLI(file) { this.options.cliPath = file; this.reload(); }
  async client() {
    if (this.rpc) return this.rpc;
    const launch = this.options.launch || cliLaunch(this.options.cliPath);
    const rpc = new CodexRPC(launch, { cwd: os.homedir() }); this.rpc = rpc;
    rpc.on('notification', message => { if (this.rpc === rpc) this.notification(message); });
    rpc.on('disconnected', error => {
      if (this.rpc !== rpc || this.stopped) return;
      this.generation++; this.rpc = null; this.ready = false; this.refreshing = false; this.checking = false;
      if (!['waiting', 'paused'].includes(this.state.phase)) this.fail(error);
    });
    await rpc.connect();
    if (this.rpc !== rpc) throw new Error('连接已变化');
    this.ready = true; return rpc;
  }
  async refresh() {
    if (this.stopped || this.refreshing || ['waiting', 'paused'].includes(this.state.phase)) return;
    const generation = this.generation; this.refreshing = true; this.state.loading = true; this.nextLimits = Date.now() + 15000; this.publish();
    try {
      const rpc = await this.client(); if (generation !== this.generation) return;
      if (!this.state.account) {
        this.checking = true;
        const result = await rpc.request('account/read', { refreshToken: false });
        if (generation !== this.generation) return;
        this.checking = false;
        if (!['chatgpt', 'chatgptAuthTokens'].includes(result?.account?.type)) {
          this.logout();
          if (this.stamp !== 'missing' && this.retryCount++ < 4) this.retryTimer = setTimeout(() => { if (this.state.phase === 'waiting') { this.state.phase = 'loading'; this.state.reason = null; this.refresh(); } }, this.retryCount * 2000);
          return;
        }
        this.state.account = { email: result.account.email || null, planType: result.account.planType || null };
      }
      const result = await rpc.request('account/rateLimits/read'); if (generation !== this.generation) return;
      this.accept(result, true);
    } catch (error) { if (generation === this.generation && !this.stopped) this.fail(error); }
    finally { if (generation === this.generation) { this.refreshing = false; this.state.loading = false; this.publish(); } }
  }
  accept(result, authoritative) {
    const rows = quotaRows(result, this.state.account?.planType);
    if (!rows.some(x => x.remaining != null)) { this.fail(new Error('服务器尚未返回百分比额度')); return; }
    Object.assign(this.state, { rows, phase: 'ready', error: null, reason: null, lastUpdate: Date.now() });
    if (authoritative) this.nextLimits = Date.now() + 15000;
    if (rows.some(x => x.remaining == null) && this.partialRetries++ < 3) {
      clearTimeout(this.retryTimer); this.retryTimer = setTimeout(() => this.refresh(), this.partialRetries * 2000);
    }
    this.publish();
  }
  notification(message) {
    if (message.method === 'account/updated') {
      if (!this.ready) return;
      if (message.params?.authMode == null) { this.logout(); return; }
      if (this.checking) return;
      // Keep the same transport so Keychain-backed relogin can wake the idle reader.
      this.generation++; this.rpc?.cancelPending(); this.refreshing = false; this.clearAccount();
      Object.assign(this.state, { phase: 'loading', loading: false, reason: null }); this.partialRetries = 0; this.refresh();
    } else if (message.method === 'account/rateLimits/updated' && this.state.account && !this.refreshing && this.state.phase === 'ready') this.accept(message.params, false);
  }
  fail(error) { Object.assign(this.state, { phase: 'error', error: error.message || String(error), loading: false }); this.nextLimits = Date.now() + 15000; this.publish(); }
  async scanWork() {
    const generation = this.generation; this.nextWork = Date.now() + 2000; this.workBusy = true;
    try { const work = await this.workTracker.scan(); if (generation === this.generation && this.state.account && !this.stopped) { this.state.work = work; this.publish(); } }
    finally { this.workBusy = false; }
  }
}
module.exports = { Backend };
