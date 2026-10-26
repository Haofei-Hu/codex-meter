'use strict';
const { EventEmitter } = require('node:events');
const { spawn } = require('node:child_process');
class CodexRPC extends EventEmitter {
  constructor(launch, options = {}) { super(); this.launch = launch; this.options = options; this.id = 0; this.pending = new Map(); this.buffer = ''; this.proc = null; }
  async connect() {
    if (this.proc) return;
    const { command, args = [], env = {} } = this.launch;
    const proc = spawn(command, [...args, 'app-server'], { windowsHide: true, stdio: ['pipe', 'pipe', 'ignore'], env: { ...process.env, ...env }, ...this.options });
    this.proc = proc;
    proc.stdout.setEncoding('utf8');
    proc.stdout.on('data', data => {
      if (this.proc !== proc) return;
      this.buffer += data;
      if (this.buffer.length > 16 * 1024 * 1024) { this.close(); return; }
      let end;
      while ((end = this.buffer.indexOf('\n')) >= 0) {
        const line = this.buffer.slice(0, end); this.buffer = this.buffer.slice(end + 1);
        let message; try { message = JSON.parse(line); } catch { continue; }
        if (message.id != null && this.pending.has(message.id)) {
          const pending = this.pending.get(message.id); this.pending.delete(message.id); clearTimeout(pending.timeout);
          if (message.error) { const error = new Error(message.error.message || 'Codex request failed'); error.code = message.error.code; pending.reject(error); }
          else pending.resolve(message.result);
        } else if (message.method) this.emit('notification', message);
      }
    });
    const ended = error => {
      if (this.proc !== proc) return;
      this.proc = null;
      for (const item of this.pending.values()) { clearTimeout(item.timeout); item.reject(error); }
      this.pending.clear(); this.emit('disconnected', error);
    };
    proc.on('error', error => ended(error)); proc.on('exit', () => ended(new Error('Codex 连接已断开')));
    await this.request('initialize', { clientInfo: { name: 'codex_meter', title: 'Codex Meter', version: '1.5.2' } });
    this.send({ method: 'initialized', params: {} });
  }
  send(message) {
    if (!this.proc?.stdin.writable) throw new Error('Codex 未连接');
    this.proc.stdin.write(JSON.stringify(message) + '\n');
  }
  request(method, params) {
    const id = ++this.id;
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => { this.pending.delete(id); reject(new Error('Codex 请求超时')); }, 25000);
      this.pending.set(id, { resolve, reject, timeout });
      try { this.send({ id, method, ...(params == null ? {} : { params }) }); } catch (error) { clearTimeout(timeout); this.pending.delete(id); reject(error); }
    });
  }
  cancelPending() {
    for (const item of this.pending.values()) { clearTimeout(item.timeout); item.reject(new Error('连接状态已变化')); }
    this.pending.clear();
  }
  close() {
    const proc = this.proc; this.proc = null; this.buffer = '';
    for (const item of this.pending.values()) { clearTimeout(item.timeout); item.reject(new Error('连接已重新建立')); }
    this.pending.clear();
    if (proc) { proc.stdin.destroy(); proc.stdout.destroy(); proc.kill(); }
  }
}
module.exports = { CodexRPC };
