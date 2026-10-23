const assert = require('node:assert/strict');
const { execFileSync, execFile } = require('node:child_process');
const { promisify } = require('node:util');
const fs = require('node:fs');
const path = require('node:path');

const localDB = 'postgres://postgres:postgres@localhost:5432/fu_pilot_qa';
function guard() {
  assert.equal(process.env.FU_BROWSER_QA, '1', 'QA must be explicitly enabled');
  assert.equal(process.env.DATABASE_URL, localDB, 'Only the disposable local database is supported');
}
guard();
const appContainer = process.env.FU_QA_APP_CONTAINER || 'fu-pilot-qa';
const token = process.env.FU_SMS_API_KEY || 'fu-sim-local-rehearsal-only';
assert.ok(token.startsWith('fu-sim-'));
const results = path.join(__dirname, 'results');
fs.mkdirSync(results, { recursive: true });
const docker = (...args) => execFileSync('docker', args, { stdio: 'pipe', timeout: 45_000 });
const rpc = (expression) => docker('exec', appContainer, '/app/bin/fu', 'rpc', expression).toString();
const rpcAsync = async (expression) => (await promisify(execFile)('docker', [
  'exec', appContainer, '/app/bin/fu', 'rpc', expression,
], { timeout: 150_000, maxBuffer: 8 * 1024 * 1024 })).stdout;
const pause = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
async function sms(route, body) {
  const response = await fetch(`http://localhost:9166${route}`, {
    method: body ? 'POST' : 'GET', headers: { authorization: `AccessKey ${token}`, 'content-type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(5000),
  });
  assert.equal(response.status, 200);
  return response.json();
}
async function waitReady(status = 200, port = 4000) {
  const start = performance.now();
  while (performance.now() - start < 30_000) {
    try {
      const response = await fetch(`http://localhost:${port}/healthz`, { signal: AbortSignal.timeout(2000) });
      if (response.status === status) {
        assert.deepEqual(await response.json(), { status: status === 200 ? 'ok' : 'unavailable' });
        return Math.round(performance.now() - start);
      }
    } catch { /* Waiting for a deliberately interrupted release. */ }
    await pause(250);
  }
  throw new Error(`Readiness did not reach ${status} within 30 seconds on ${port}`);
}
const percentile = (values, p = 0.95) => [...values].sort((a, b) => a - b)[Math.ceil(values.length * p) - 1];
const save = (name, value) => fs.writeFileSync(path.join(results, name), JSON.stringify(value, null, 2));
module.exports = { guard, appContainer, results, docker, rpc, rpcAsync, pause, sms, waitReady, percentile, save };
