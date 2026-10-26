'use strict';
const fs = require('node:fs'), path = require('node:path'), readline = require('node:readline');
const root = process.argv[2];
function read() { try { return JSON.parse(fs.readFileSync(path.join(root, 'account-state.json'), 'utf8')); } catch { return null; } }
readline.createInterface({ input: process.stdin }).on('line', async line => {
  const request = JSON.parse(line); fs.appendFileSync(path.join(root, 'rpc-log.jsonl'), JSON.stringify({ method: request.method }) + '\n');
  if (request.id == null) return;
  const state = read(); let result;
  if (request.method === 'initialize') result = {};
  else if (request.method === 'account/read') result = { account: state ? { type: 'chatgpt', email: state.email, planType: state.plan } : null };
  else if (request.method === 'account/rateLimits/read') {
    if (state?.delay) await new Promise(resolve => setTimeout(resolve, state.delay));
    const bucket = { limitId: 'codex', planType: state?.plan, primary: { usedPercent: state?.used ?? 0, windowDurationMins: 300, resetsAt: Date.now() / 1000 + 7200 }, secondary: state?.weeklyUsed == null ? null : { usedPercent: state.weeklyUsed, windowDurationMins: 10080, resetsAt: Date.now() / 1000 + 86400 } };
    result = { rateLimits: bucket, rateLimitsByLimitId: { codex: bucket } };
  } else result = {};
  process.stdout.write(JSON.stringify({ id: request.id, result }) + '\n');
});
