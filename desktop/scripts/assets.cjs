'use strict';
const fs = require('node:fs'), path = require('node:path');
const { PNG } = require('pngjs');
const source = path.resolve(__dirname, '../../Assets/AppIcon.png');
const original = PNG.sync.read(fs.readFileSync(source));
const icon = new PNG({ width: 256, height: 256 });
for (let y = 0; y < 256; y++) for (let x = 0; x < 256; x++) {
  const from = (Math.floor(y * original.height / 256) * original.width + Math.floor(x * original.width / 256)) * 4;
  original.data.copy(icon.data, (y * 256 + x) * 4, from, from + 4);
}
const png = PNG.sync.write(icon);
const header = Buffer.alloc(22); header.writeUInt16LE(1, 2); header.writeUInt16LE(1, 4);
header[6] = 0; header[7] = 0; header.writeUInt16LE(1, 10); header.writeUInt16LE(32, 12); header.writeUInt32LE(png.length, 14); header.writeUInt32LE(22, 18);
fs.mkdirSync(path.resolve(__dirname, '../assets'), { recursive: true });
fs.writeFileSync(path.resolve(__dirname, '../assets/icon.png'), PNG.sync.write(original));
fs.writeFileSync(path.resolve(__dirname, '../assets/icon.ico'), Buffer.concat([header, png]));
