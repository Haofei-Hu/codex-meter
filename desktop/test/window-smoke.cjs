'use strict';
const assert = require('node:assert/strict');
const { execFile } = require('node:child_process');
const { promisify } = require('node:util');
const { setTimeout: delay } = require('node:timers/promises');
const fs = require('node:fs'), path = require('node:path');
async function inspect(win) {
  return win.webContents.executeJavaScript(`(() => {
    const box = selector => { const r = document.querySelector(selector).getBoundingClientRect(); return { x:r.x, y:r.y, width:r.width, height:r.height, right:r.right, bottom:r.bottom }; };
    const body = document.getElementById('card-body');
    return { width:innerWidth, height:innerHeight, card:box('#card'), title:box('.header h1'), footer:box('.refresh'), more:box('.more'), grip:box('.grip'), ring:box('.ring'), scroll:body.scrollHeight > body.clientHeight + 1 };
  })()`);
}
function visible(box, viewport, label) {
  assert.ok(box.x >= 0 && box.y >= 0 && box.right <= viewport.width + 1 && box.bottom <= viewport.height + 1, `${label} is clipped: ${JSON.stringify({box, viewport})}`);
}
async function windowsHitTest(win, screen, view) {
  if (process.platform !== 'win32') return;
  const bounds = win.getBounds(), handle = win.getNativeWindowHandle();
  const hwnd = (handle.length === 8 ? handle.readBigUInt64LE() : BigInt(handle.readUInt32LE())).toString();
  const samples = ['title', 'more', 'grip', ...(!view.scroll ? ['ring'] : [])].map(key => {
    const rect = view[key];
    const point = screen.dipToScreenPoint({ x: Math.round(bounds.x + rect.x + rect.width / 2), y: Math.round(bounds.y + rect.y + rect.height / 2) });
    return { key, x: point.x, y: point.y, expected: ['title', 'ring'].includes(key) ? 2 : 1 };
  });
  // Read the actual Windows non-client hit map. No global pointer movement or input injection.
  const script = `Add-Type -TypeDefinition @'\nusing System; using System.Runtime.InteropServices;\npublic static class MeterHit {\n [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, UIntPtr w, IntPtr l, uint f, uint t, out UIntPtr result);\n public static ulong Read(long h, int x, int y) { UIntPtr r; var ok=SendMessageTimeout(new IntPtr(h),0x84,UIntPtr.Zero,new IntPtr((y<<16)|(x&0xffff)),2,3000,out r); if(ok==IntPtr.Zero) throw new Exception("Hit test timed out"); return r.ToUInt64(); }\n}\n'@\n` + samples.map(p => `Write-Output '${p.key}:'; Write-Output ([MeterHit]::Read(${hwnd}, ${p.x}, ${p.y}))`).join('\n');
  const { stdout } = await promisify(execFile)('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', script], { timeout: 20000, windowsHide: true });
  const values = stdout.trim().split(/\s+/);
  for (const sample of samples) { const index = values.indexOf(sample.key + ':'); assert.ok(index >= 0); assert.equal(Number(values[index + 1]), sample.expected, `Native Windows drag hit map: ${sample.key}`); }
}
module.exports = async function windowSmoke({ win, screen, state, updateState, setArea, setScale }) {
  const baseline = structuredClone(state);
  const shot = async suffix => { if (process.env.CODEX_METER_SCREENSHOT) { const file = process.env.CODEX_METER_SCREENSHOT, ext = path.extname(file); fs.writeFileSync(file.slice(0, -ext.length) + suffix + ext, (await win.webContents.capturePage()).toPNG()); } };
  const verify = async label => { await delay(450); const view = await inspect(win); for (const key of ['title','footer','grip','card']) visible(view[key], view, label + ' ' + key); return view; };
  setArea({ width: 1093, height: 568 }); setScale(1.6);
  let view = await verify('Plus / 125% work area'); await windowsHitTest(win, screen, view); await shot('-plus-small');
  const busy = structuredClone(baseline); busy.work.tasks = [0,1].map(i => ({ ...busy.work.tasks[0], id:'task-'+i, planTotal:5, planDone:2, detail:'正在运行多个任务，验证进度增加后卡片仍保持完整显示。'.repeat(4) })); busy.work.activeCount=2;
  updateState(busy); setArea({ width: 960, height: 420 });
  view = await verify('Plus / tall content'); assert.equal(view.scroll, true); await windowsHitTest(win, screen, view); await shot('-plus-scroll');
  const pro = structuredClone(baseline); pro.account.planType='pro'; pro.rows=pro.rows.slice(1); updateState(pro); setArea({ width:1093, height:568 }); setScale(1);
  view = await verify('Pro'); await windowsHitTest(win, screen, view);
  updateState(baseline); setArea(null); setScale(1); await verify('restored Plus');
  console.log('PASS card regression: Plus/Pro native drag regions, short/high-DPI work areas, overflow, pinned controls, display changes');
};
