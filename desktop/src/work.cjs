'use strict';
const fs = require('node:fs/promises'), path = require('node:path');
const time = value => typeof value === 'number' ? value * 1000 : Date.parse(value);
const clean = value => String(value || '').replace(/[\r\n]/g, ' ').trim().slice(0, 160);
function consume(task, record) {
  const p = record.payload || {}, kind = p.type, timestamp = time(record.timestamp) || task.updatedAt || 0;
  if (record.type === 'session_meta') { task.id = p.id || task.id; return; }
  if (record.type === 'event_msg') {
    if (kind === 'task_started') Object.assign(task, { turnID: p.turn_id, active: true, stage: '进行中', startedAt: time(p.started_at) || timestamp, finishedAt: null, detail: '', calls: [], planDone: 0, planTotal: 0 });
    else if (['task_complete', 'turn_aborted'].includes(kind)) {
      if (p.turn_id && task.turnID && p.turn_id !== task.turnID) return;
      Object.assign(task, { active: false, stage: kind === 'task_complete' ? '已完成' : '已中断', finishedAt: time(p.completed_at) || timestamp, calls: [] });
    } else if (['approval_requested', 'user_input_requested'].includes(kind) && task.active) task.stage = '等待操作';
    else if (['plan_update', 'plan_updated'].includes(kind)) plan(task, p.plan);
  } else if (record.type === 'response_item' && task.active) {
    if (['function_call', 'custom_tool_call'].includes(kind)) {
      if (p.call_id && !task.calls.includes(p.call_id)) task.calls.push(p.call_id);
      task.stage = '执行工具';
      if (p.name === 'update_plan') { try { plan(task, JSON.parse(p.arguments).plan); } catch {} }
    } else if (['function_call_output', 'custom_tool_call_output'].includes(kind)) {
      task.calls = task.calls.filter(x => x !== p.call_id); task.stage = task.calls.length ? '执行工具' : '进行中';
    } else if (kind === 'message' && p.role === 'assistant' && p.phase === 'commentary') task.detail = clean((p.content || []).map(x => x.text || '').join(' '));
  }
  task.updatedAt = Math.max(task.updatedAt || 0, timestamp);
}
function plan(task, steps) {
  if (!Array.isArray(steps) || !steps.length) return;
  task.planDone = steps.filter(x => x.status === 'completed').length; task.planTotal = steps.length;
  const current = steps.find(x => x.status === 'in_progress'); if (current) task.detail = clean(current.step);
}
class WorkTracker {
  constructor(root) { this.root = root; this.cursors = new Map(); }
  clear() { this.cursors.clear(); }
  async scan(now = Date.now()) {
    const names = new Map();
    try { const content = await fs.readFile(path.join(this.root, 'session_index.jsonl'), 'utf8'); for (const line of content.slice(-1024 * 1024).split('\n')) { try { const v = JSON.parse(line); if (v.id && v.thread_name) names.set(v.id, clean(v.thread_name)); } catch {} } } catch {}
    const seen = new Set();
    const walk = async dir => {
      for (const entry of await fs.readdir(dir, { withFileTypes: true })) {
        if (entry.isSymbolicLink()) continue;
        const file = path.join(dir, entry.name);
        if (entry.isDirectory()) { await walk(file); continue; }
        if (!entry.name.endsWith('.jsonl')) continue;
        const stat = await fs.stat(file); if (now - stat.mtimeMs > 86400000) continue;
        seen.add(file);
        let cursor = this.cursors.get(file);
        if (!cursor || stat.size < cursor.offset) cursor = { offset: 0, pending: Buffer.alloc(0), task: { id: entry.name, title: '本机 Codex 任务', active: false, updatedAt: 0, calls: [], planDone: 0, planTotal: 0 } };
        const handle = await fs.open(file, 'r');
        try {
          while (cursor.offset < stat.size) {
            const buffer = Buffer.alloc(Math.min(262144, stat.size - cursor.offset));
            const { bytesRead } = await handle.read(buffer, 0, buffer.length, cursor.offset); if (!bytesRead) break;
            cursor.offset += bytesRead; cursor.pending = Buffer.concat([cursor.pending, buffer.subarray(0, bytesRead)]);
            let end;
            while ((end = cursor.pending.indexOf(10)) >= 0) {
              const line = cursor.pending.subarray(0, end); cursor.pending = cursor.pending.subarray(end + 1);
              try { consume(cursor.task, JSON.parse(line.toString('utf8'))); } catch {}
            }
            if (cursor.pending.length > 16e6) cursor.pending = Buffer.alloc(0);
          }
        } finally { await handle.close(); }
        cursor.task.title = names.get(cursor.task.id) || cursor.task.title;
        this.cursors.set(file, cursor);
      }
    };
    try { await walk(path.join(this.root, 'sessions')); } catch { return { state: 'unavailable', activeCount: 0, tasks: [] }; }
    for (const file of this.cursors.keys()) if (!seen.has(file)) this.cursors.delete(file);
    const all = [...this.cursors.values()].map(x => x.task).filter(x => x.startedAt).sort((a, b) => b.updatedAt - a.updatedAt);
    const active = all.filter(x => x.active);
    return { state: active.length ? 'running' : 'idle', activeCount: active.length, tasks: (active.length ? active.slice(0, 2) : all.filter(x => now - x.updatedAt < 900000).slice(0, 1)).map(x => ({ ...x, calls: undefined })) };
  }
}
module.exports = { WorkTracker, consume, time, clean };
