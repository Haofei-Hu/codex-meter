'use strict';
const query = new URLSearchParams(location.search), view = query.get('view') || 'desktop', preview = query.get('preview') === '1';
document.body.classList.add(view === 'desktop' ? 'desktop' : 'popup', view);
const cardTop = document.getElementById('card-header'), cardBottom = document.getElementById('card-footer');
const card = document.getElementById('card'), shell = document.getElementById('shell'), content = document.getElementById('content');
let current, dragging = false, resizeScheduled = false, message = '';
const clamp = (x, a, b) => Math.max(a, Math.min(b, x));
const html = value => String(value ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
function color(amount) {
  const value = clamp(Number(amount) || 0, 0, 100), green = [0.42, 0.92, 0.77], orange = [1, 0.58, 0.18], red = [1, 0.25, 0.28];
  const [a, b, t] = value >= 30 ? [green, orange, (100 - value) / 70] : [orange, red, (30 - value) / 30], mix = t * t * (3 - 2 * t);
  return `rgb(${a.map((v, i) => Math.round((v + (b[i] - v) * mix) * 255)).join(',')})`;
}
const now = () => current?.now || Date.now();
function elapsed(milliseconds) { const s = Math.max(0, Math.floor(milliseconds / 1000)); return s >= 3600 ? `${Math.floor(s / 3600)}小时 ${Math.floor(s % 3600 / 60)}分钟` : s >= 60 ? `${Math.floor(s / 60)}分 ${s % 60}秒` : `${s}秒`; }
function date(value) { return new Intl.DateTimeFormat('zh-CN', { month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hour12: false }).format(new Date(value)); }
function countdown(value) {
  const seconds = Math.max(0, Math.floor((value - now()) / 1000)); if (!seconds) return '等待服务器更新';
  const days = Math.floor(seconds / 86400), hours = Math.floor(seconds % 86400 / 3600), mins = Math.floor(seconds % 3600 / 60);
  return days ? `${days}天 ${hours}小时后重置` : hours ? `${hours}小时 ${mins}分钟后重置` : `${Math.max(1, mins)}分钟后重置`;
}
function waiting() { return ['waiting', 'paused'].includes(current.phase); }
function settings() {
  const p = current.prefs;
  return `<div class="settings"><div class="setting-line"><span>桌面卡片大小</span><span id="scale-label">${Math.round(p.scale * 100)}%</span><button class="small-btn" data-action="reset-scale">还原</button></div>
    <input aria-label="桌面卡片缩放" type="range" min="0.75" max="1.6" step="0.05" value="${p.scale}" data-setting="scale">
    <div><button class="small-btn" data-action="recheck">重新检测账号</button></div>
    ${[['desktopVisible', '显示桌面卡片'], ['login', '登录时启动'], ['followHost', '跟随 Codex 退出暂停'], ['alwaysOnTop', '桌面卡片置顶']].map(([key, label]) => `<div class="setting-line"><label>${label}<input type="checkbox" data-setting="${key}" ${p[key] ? 'checked' : ''}></label></div>`).join('')}
    <div class="settings-bottom"><button class="small-btn" data-action="select-cli">选择 Codex 程序…</button><button class="small-btn" data-action="quit">退出</button></div>
    <div class="notice">Windows 使用系统托盘；Linux 托盘位置由桌面环境决定。任务进度只读本机记录。</div></div>`;
}
function work() {
  const w = current.work || { state: 'loading', tasks: [], activeCount: 0 };
  const labels = { loading: '读取工作状态…', running: w.activeCount > 1 ? `${w.activeCount} 个任务进行中` : '工作中', idle: '空闲', unavailable: '任务状态暂不可用', paused: '更新已暂停' };
  return `<section class="work" aria-label="实时工作进度"><div class="work-header"><span class="wave">⌁</span><strong>实时工作进度</strong><span class="work-label ${w.state === 'running' ? 'running' : ''}">${labels[w.state]}</span></div>
    ${w.tasks.map(task => `<article class="task"><div class="task-title" title="${html(task.title)}">${html(task.title)}</div><div class="task-meta">${task.active ? '<span class="spinner" aria-label="正在工作"></span>' : ''}<span>${html(task.stage)}</span><span class="task-time">${task.active ? '已运行' : '耗时'} ${elapsed((task.finishedAt || now()) - task.startedAt)}</span></div>
      ${task.planTotal ? `<div class="plan"><span style="width:${clamp(task.planDone / task.planTotal * 100, 0, 100)}%"></span></div><div class="work-source">计划步骤 ${task.planDone}/${task.planTotal} 完成</div>` : ''}
      ${task.detail ? `<p class="detail">${html(task.detail)}</p>` : ''}${task.active && now() - task.updatedAt > 120000 ? `<div class="warning">${Math.floor((now() - task.updatedAt) / 60000)} 分钟未收到新记录</div>` : ''}</article>`).join('')}
    ${!w.tasks.length ? `<p class="detail">${({ idle: '暂无运行中的本机任务', paused: '登录并打开 Codex 后自动恢复', unavailable: '未找到可读取的本机任务记录' })[w.state] || '正在读取本机任务记录…'}</p>` : ''}
    <p class="work-source">本机任务记录 · 每 2 秒更新</p></section>`;
}
function render(state) {
  current = state;
  if (dragging || document.activeElement?.type === 'range') { layout(); return; }
  if (view === 'settings') { cardTop.innerHTML = '<div class="settings-title">卡片设置<button class="close" data-action="close-popup" aria-label="关闭设置">×</button></div>'; content.innerHTML = settings(); cardBottom.innerHTML = ''; }
  else {
    const age = state.lastUpdate ? Math.max(0, Math.floor((now() - state.lastUpdate) / 1000)) : null;
    const stale = waiting() || !!state.error || age == null || age > 35;
    const status = waiting() ? '已暂停' : state.loading ? '同步中' : stale ? '待更新' : age < 2 ? '刚更新' : `${age}秒前`;
    const plan = ({ plus: 'Plus', pro: 'Pro', prolite: 'Pro Lite', free: 'Free', team: 'Team', business: 'Business', enterprise: 'Enterprise', edu: 'Edu' })[state.account?.planType] || state.account?.planType || 'ChatGPT';
    const account = state.account ? `${plan}${state.account.email ? ' · ' + state.account.email : ''}` : state.loading ? '正在识别当前账号…' : state.phase === 'error' ? '连接失败 · 尚未读取登录状态' : '未登录 ChatGPT 账号';
    cardTop.innerHTML = `${preview ? '<div class="demo">界面演示数据</div>' : ''}<header class="header" title="拖动这里移动桌面卡片"><span class="logo">&lt;/&gt;</span><h1>Codex 剩余额度</h1><span class="status"><i class="dot ${stale ? 'stale' : ''}"></i>${status}</span>${view === 'desktop' ? '<button class="more" data-action="settings" aria-label="卡片设置">···</button>' : ''}</header>`;
    content.innerHTML = `<div class="account" title="${html(account)}">${html(account)}</div>
      ${!state.rows.length ? `<div class="empty"><strong>—</strong><span>${html(state.reason || (state.loading ? '正在读取你的 Codex 额度…' : '暂未获取到额度'))}</span></div>` : `<div class="quotas">${state.rows.map(row => {
        const remaining = row.remaining ?? 0, length = 2 * Math.PI * 44;
        return `<div class="quota"><div class="ring"><svg viewBox="0 0 94 94" aria-hidden="true"><circle class="track" cx="47" cy="47" r="44"/><circle class="fill" cx="47" cy="47" r="44" style="stroke:${color(remaining)};stroke-dasharray:${length};stroke-dashoffset:${length * (1 - remaining / 100)}"/></svg><div class="percent"><span class="amount">${row.remaining == null ? '—' : remaining}</span><span class="suffix">${row.remaining == null ? '未返回' : '% 剩余'}</span></div></div><div class="quota-info"><h2>${html(row.group === 'Codex' ? row.label : row.group + ' · ' + row.label)}</h2>${row.resetsAt ? `<div class="reset">${countdown(row.resetsAt)}</div><div class="date">${date(row.resetsAt)}</div>` : `<div class="date">${row.remaining == null ? '等待服务器返回额度' : '未提供重置时间'}</div>`}</div></div>`;
      }).join('')}</div>`}
      ${work()}${state.error || message ? `<div class="error">${html(message || state.error)}</div>` : ''}${view !== 'desktop' ? settings() : ''}`;
    cardBottom.innerHTML = `<div class="divider"></div><footer class="footer"><div><div class="sync-time">${state.lastUpdate ? '更新于 ' + new Date(state.lastUpdate).toLocaleTimeString('zh-CN', { hour12: false }) : '尚未同步'}</div><div class="sync-next">${html(state.reason || `每 15 秒同步 · ${Math.max(0, Math.floor((state.nextUpdate - now()) / 1000))} 秒后刷新`)}</div></div><button class="refresh" data-action="refresh" aria-label="立即刷新" ${state.loading || waiting() ? 'disabled' : ''}>↻</button></footer>`;
  }
  layout();
}
function layout() {
  if (!current || resizeScheduled) return;
  resizeScheduled = true;
  requestAnimationFrame(() => {
    resizeScheduled = false;
    // Measure unscaled content, including hidden overflow, rather than the clipped window.
    const style = getComputedStyle(card);
    const vertical = ['paddingTop', 'paddingBottom', 'borderTopWidth', 'borderBottomWidth'].reduce((n, key) => n + parseFloat(style[key]), 0);
    const natural = { width: card.offsetWidth, height: Math.ceil(cardTop.offsetHeight + content.offsetHeight + cardBottom.offsetHeight + vertical) };
    if (view === 'desktop') {
      const area = current.viewport || { width: window.screen.availWidth, height: window.screen.availHeight };
      const fit = window.meterGeometry.cardLayout(natural, current.prefs.scale, area);
      shell.style.transform = `scale(${fit.scale})`;
      card.style.maxHeight = `${fit.maxCardHeight}px`;
      card.classList.toggle('scrolling', fit.scroll);
      window.meter?.resize(natural);
    } else {
      shell.style.transform = 'none';
      window.meter?.resize({ width: natural.width + 16, height: natural.height + 16 });
    }
  });
}
async function invoke(action) {
  try {
    message = '';
    if (action === 'reset-scale') await window.meter?.preference('scale', 1);
    else await window.meter?.action(action);
  } catch (error) { message = error.message || String(error); render(current); }
}
document.addEventListener('click', event => { const target = event.target.closest('[data-action]'); if (target && !target.disabled) invoke(target.dataset.action); });
document.addEventListener('input', async event => {
  const key = event.target.dataset.setting; if (!key) return;
  const value = key === 'scale' ? Number(event.target.value) : event.target.checked;
  if (key === 'scale') { current.prefs.scale = value; const text = document.getElementById('scale-label'); if (text) text.textContent = `${Math.round(value * 100)}%`; layout(); }
  try { await window.meter?.preference(key, value); } catch (error) { message = error.message; render(current); }
});
document.addEventListener('focusout', event => { if (event.target.type === 'range') setTimeout(() => render(current), 0); });
document.addEventListener('keydown', event => { if (event.key === 'Escape' && view !== 'desktop') invoke('close-popup'); });
if (view === 'desktop') {
  const grip = document.createElement('button'); grip.className = 'grip'; grip.setAttribute('aria-label', '拖动右下角调整大小'); grip.title = '拖动右下角调整大小'; card.append(grip);
  let start;
  grip.addEventListener('pointerdown', event => { event.preventDefault(); dragging = true; start = { x: event.screenX, y: event.screenY, scale: current.prefs.scale, height: card.offsetHeight }; grip.setPointerCapture(event.pointerId); });
  grip.addEventListener('pointermove', event => {
    if (!dragging) return;
    const dx = (event.screenX - start.x) / 332, dy = (event.screenY - start.y) / start.height;
    const scale = clamp(start.scale + (Math.abs(dx) >= Math.abs(dy) ? dx : dy), 0.75, 1.6);
    current.prefs.scale = scale; layout(); window.meter?.preference('scale', scale)?.catch(() => {});
  });
  const end = () => { if (dragging) { dragging = false; render(current); } };
  grip.addEventListener('pointerup', end); grip.addEventListener('pointercancel', end); grip.addEventListener('lostpointercapture', end);
}
new ResizeObserver(layout).observe(content);
if (window.meter) window.meter.subscribe(render);
else if (preview) {
  const time = Date.now();
  const example = { phase: 'ready', now: time, lastUpdate: time, nextUpdate: time + 15000, account: { planType: 'plus', email: 'demo@example.test' }, rows: [
    { id: 'short', group: 'Codex', label: '5 小时额度', remaining: 74, resetsAt: time + 7200000 }, { id: 'week', group: 'Codex', label: '每周额度', remaining: 89, resetsAt: time + 5 * 86400000 }
  ], work: { state: 'running', activeCount: 1, tasks: [{ id: 'demo', title: '制作跨平台额度小组件', active: true, stage: '执行工具', startedAt: time - 140000, updatedAt: time, detail: '正在验证 Windows 与 Linux 的桌面卡片、托盘和账号同步。', planTotal: 0 }] }, prefs: { scale: 1, desktopVisible: true, followHost: true, login: false, alwaysOnTop: false } };
  render(example);
} else content.textContent = '应用连接未建立，请重新启动 Codex Meter。';
