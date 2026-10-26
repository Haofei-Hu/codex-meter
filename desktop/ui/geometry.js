/* Shared CSS-pixel / Electron-DIP layout. Keep both sides on the same scale. */
(function (root) {
  'use strict';
  const clamp = (value, low, high) => Math.max(low, Math.min(high, value));
  function cardLayout(natural, requestedScale, area) {
    const width = Math.max(1, natural.width), height = Math.max(1, natural.height);
    const availableWidth = Math.max(1, area.width - 32), availableHeight = Math.max(1, area.height - 32);
    const requested = clamp(requestedScale, 0.75, 1.6);
    // Preserve readable text; if the card is still too tall at 75%, scroll its body.
    const scale = Math.min(requested, availableWidth / width, Math.max(0.75, availableHeight / height));
    const maxCardHeight = availableHeight / scale;
    return { scale, maxCardHeight, scroll: height > maxCardHeight + 0.5,
      width: Math.ceil(width * scale) + 16, height: Math.ceil(Math.min(height, maxCardHeight) * scale) + 16 };
  }
  function cardFrame(current, layout, area) {
    return { x: Math.round(clamp(current.x, area.x + 8, area.x + area.width - layout.width - 8)),
      y: Math.round(clamp(current.y, area.y + 8, area.y + area.height - layout.height - 8)), width: layout.width, height: layout.height };
  }
  const api = { cardLayout, cardFrame };
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.meterGeometry = api;
})(typeof window === 'object' ? window : globalThis);
