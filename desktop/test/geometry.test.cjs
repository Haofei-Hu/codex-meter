'use strict';
const test = require('node:test'), assert = require('node:assert/strict');
const { cardLayout, cardFrame } = require('../ui/geometry.js');
test('Plus card fits short/high-DPI work areas at every saved scale', () => {
  for (const area of [{ x: 0, y: 0, width: 1366, height: 728 }, { x: 0, y: 0, width: 1093, height: 568 }, { x: -1536, y: 40, width: 1536, height: 824 }, { x: 0, y: 0, width: 800, height: 420 }]) {
    for (const height of [420, 560, 750, 1100, 3000]) for (const scale of [0.75, 1, 1.25, 1.5, 1.6]) {
      const fit = cardLayout({ width: 332, height }, scale, area);
      const frame = cardFrame({ x: area.x + area.width - 30, y: area.y + area.height - 20 }, fit, area);
      assert.ok(frame.x >= area.x + 8 && frame.x + frame.width <= area.x + area.width - 8);
      assert.ok(frame.y >= area.y + 8 && frame.y + frame.height <= area.y + area.height - 8);
      assert.ok(fit.scale <= scale && fit.scale >= 0.75);
      assert.equal(fit.scroll, height > fit.maxCardHeight + 0.5);
      assert.ok(fit.scroll || height * fit.scale <= frame.height - 16 + 1);
    }
  }
});
test('automatic fit does not overwrite requested scale and supports negative monitor coordinates', () => {
  const natural = { width: 332, height: 760 };
  const small = cardLayout(natural, 1.6, { width: 1024, height: 700 });
  const large = cardLayout(natural, 1.6, { width: 2560, height: 1600 });
  assert.ok(small.scale < 1); assert.equal(large.scale, 1.6);
  assert.deepEqual(cardFrame({ x: -1400, y: 60 }, large, { x: -2560, y: 0, width: 2560, height: 1600 }), { x: -1400, y: 60, width: 548, height: 1232 });
});
