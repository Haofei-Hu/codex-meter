'use strict';
const clamp = (value, min, max) => Math.max(min, Math.min(max, value));
function quotaColor(amount) {
  const value = clamp(Number(amount) || 0, 0, 100);
  const green = [0.42, 0.92, 0.77], orange = [1, 0.58, 0.18], red = [1, 0.25, 0.28];
  const [a, b, t] = value >= 30 ? [green, orange, (100 - value) / 70] : [orange, red, (30 - value) / 30];
  const mix = t * t * (3 - 2 * t);
  return a.map((x, i) => Math.round((x + (b[i] - x) * mix) * 255));
}
function label(minutes) {
  if (minutes === 10080) return '每周额度';
  if (!Number.isFinite(minutes)) return '额度';
  if (minutes >= 1440) return `${Math.floor(minutes / 1440)} 天额度`;
  if (minutes >= 60) return `${minutes / 60} 小时额度`;
  return `${minutes} 分钟额度`;
}
function quotaRows(result, plan) {
  const legacy = result?.rateLimits;
  let buckets = Object.entries(result?.rateLimitsByLimitId || {});
  if (!buckets.length && legacy) buckets = [[legacy.limitId || 'codex', legacy]];
  let rows = buckets.flatMap(([key, bucket]) => {
    const fallback = key === 'codex' || legacy?.limitId === key ? legacy : null;
    return ['primary', 'secondary'].flatMap(slot => {
      const window = bucket?.[slot] ?? fallback?.[slot];
      if (!window || !Number.isFinite(window.usedPercent)) return [];
      return [{ id: `${key}-${slot}`, group: key === 'codex' ? 'Codex' : (bucket.limitName || key),
        label: label(window.windowDurationMins), minutes: window.windowDurationMins ?? null,
        remaining: Math.floor(clamp(100 - window.usedPercent, 0, 100)), usedPercent: window.usedPercent,
        resetsAt: Number.isFinite(window.resetsAt) ? window.resetsAt * 1000 : null }];
    });
  }).sort((a, b) => (a.group === b.group ? (a.minutes ?? Infinity) - (b.minutes ?? Infinity) : a.group === 'Codex' ? -1 : b.group === 'Codex' ? 1 : a.group.localeCompare(b.group)));
  if (String(plan || '').toLowerCase() === 'plus') {
    const main = rows.filter(x => x.group === 'Codex');
    const short = main.filter(x => (x.minutes ?? 300) < 10080), week = main.filter(x => (x.minutes ?? 0) >= 10080);
    const unknown = (id, minutes) => ({ id, group: 'Codex', label: label(minutes), minutes, remaining: null, resetsAt: null });
    rows = [...(short.length ? short : [unknown('plus-short', 300)]), ...(week.length ? week : [unknown('plus-weekly', 10080)]), ...rows.filter(x => x.group !== 'Codex')];
  }
  return rows;
}
function menuFrame(anchor, size, area) {
  const margin = 8, width = Math.min(size.width, area.width - 16), height = Math.min(size.height, area.height - 16);
  const x = clamp(anchor.x + anchor.width / 2 - width / 2, area.x + margin, area.x + area.width - width - margin);
  // Prefer above a bottom taskbar, below a top bar. Clamp on every monitor.
  const below = anchor.y + anchor.height + 4;
  const y = below + height <= area.y + area.height - margin ? below : anchor.y - height - 4;
  return { x: Math.round(x), y: Math.round(clamp(y, area.y + margin, area.y + area.height - height - margin)), width: Math.round(width), height: Math.round(height) };
}
module.exports = { clamp, quotaColor, quotaRows, label, menuFrame };
