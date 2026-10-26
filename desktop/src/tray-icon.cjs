'use strict';
const { PNG } = require('pngjs');
const { quotaColor } = require('./model.cjs');
function trayPNG(rows, busy = false) {
  const image = new PNG({ width: 32, height: 32 });
  const pixel = (x, y, color) => { const i = (y * 32 + x) * 4; image.data[i] = color[0]; image.data[i + 1] = color[1]; image.data[i + 2] = color[2]; image.data[i + 3] = 255; };
  if (!rows.length) {
    for (let y = 3; y < 29; y++) for (let x = 3; x < 29; x++) { const d = Math.hypot(x - 15.5, y - 15.5); if (d > 9 && d < 12) pixel(x, y, [145, 158, 165]); }
  } else {
    rows.slice(0, 2).forEach((row, index) => {
      const top = rows.length > 1 ? (index ? 20 : 6) : 12;
      const amount = row.remaining ?? 0, color = quotaColor(amount);
      for (let y = top; y < top + 7; y++) for (let x = 2; x < 30; x++) pixel(x, y, x - 2 < 28 * amount / 100 ? color : [79, 91, 96]);
    });
  }
  if (busy) for (let y = 0; y < 5; y++) for (let x = 27; x < 32; x++) pixel(x, y, [107, 235, 196]);
  return PNG.sync.write(image);
}
module.exports = { trayPNG };
