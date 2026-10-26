'use strict';
const test = require('node:test'), assert = require('node:assert/strict');
const { quotaRows, quotaColor, menuFrame } = require('../src/model.cjs');
const { trayPNG } = require('../src/tray-icon.cjs');
const { PNG } = require('pngjs');
const win = (usedPercent, windowDurationMins) => ({ usedPercent, windowDurationMins, resetsAt: 1800000000 });
test('quota uses remaining percentage, short before weekly, clamp, reset timestamp', () => {
  const rows = quotaRows({ rateLimitsByLimitId: { codex: { primary: win(13, 10080), secondary: win(35, 300) } } }, 'plus');
  assert.deepEqual(rows.map(r => [r.label, r.remaining]), [['5 小时额度', 65], ['每周额度', 87]]);
  assert.equal(rows[0].resetsAt, 1800000000000);
  assert.deepEqual(quotaRows({ rateLimits: { primary: win(-5, 300), secondary: win(102, 10080) } }).map(r => r.remaining), [100, 0]);
});
test('Plus keeps unavailable windows distinct from zero and merges legacy fallback', () => {
  const partial = quotaRows({ rateLimits: { primary: win(20, 300) } }, 'plus');
  assert.deepEqual(partial.map(r => r.remaining), [80, null]);
  assert.equal(partial[1].label, '每周额度');
  const rows = quotaRows({ rateLimitsByLimitId: { codex: { primary: win(10, 300) } }, rateLimits: { limitId: 'codex', secondary: win(25, 10080) } }, 'plus');
  assert.deepEqual(rows.map(r => r.remaining), [90, 75]);
  assert.deepEqual(quotaRows({}, 'plus').map(r => r.remaining), [null, null]);
  assert.deepEqual(quotaRows({ rateLimits: { primary: win(NaN, 300) } }), []);
});
test('color continuously reaches mint, orange and red; tray is two progress bars', () => {
  assert.deepEqual(quotaColor(100), [107, 235, 196]);
  assert.deepEqual(quotaColor(30), [255, 148, 46]);
  assert.deepEqual(quotaColor(0), [255, 64, 71]);
  for (let i = 1; i <= 100; i++) assert.ok(quotaColor(i).every((c, j) => Math.abs(c - quotaColor(i - 1)[j]) < 10));
  const png = PNG.sync.read(trayPNG([{ remaining: 100 }, { remaining: 10 }], true));
  assert.equal(png.width, 32); assert.equal(png.height, 32);
  assert.notDeepEqual(trayPNG([{ remaining: 100 }]), trayPNG([{ remaining: 10 }]));
});
test('tray popup stays inside visible area on top/bottom taskbars and negative monitor coordinates', () => {
  for (const area of [{ x: 0, y: 30, width: 1920, height: 1010 }, { x: -1920, y: 0, width: 1920, height: 1040 }]) {
    for (const anchor of [{ x: area.x + 1, y: 0, width: 24, height: 24 }, { x: area.x + area.width - 20, y: 1040, width: 24, height: 24 }]) {
      const f = menuFrame(anchor, { width: 348, height: 900 }, area);
      assert.ok(f.x >= area.x && f.x + f.width <= area.x + area.width);
      assert.ok(f.y >= area.y && f.y + f.height <= area.y + area.height);
    }
  }
});
