// Read-only host checks. No OTP requests, credentials or mutations.
const assert = require('node:assert/strict');
async function inspect(base, request = fetch) {
  const url = new URL(base);
  assert.equal(url.protocol, 'https:', 'A live host must use HTTPS');
  assert.equal(url.username + url.password + url.search + url.hash, '');
  assert.equal(url.pathname, '/');
  const get = (route) => request(new URL(route, url), { redirect: 'manual', signal: AbortSignal.timeout(10_000) });
  const health = await get('/healthz');
  assert.equal(health.status, 200);
  assert.deepEqual(await health.json(), { status: 'ok' });
  assert.equal(health.headers.get('x-fu-environment'), 'production');
  const login = await get('/login');
  assert.equal(login.status, 200);
  assert.equal(login.headers.get('x-fu-environment'), 'production');
  const html = await login.text();
  assert.ok(!html.includes('simulation-banner') && !html.includes('demo code:'));
  const hobbies = await get('/hobbies');
  assert.ok([302, 303].includes(hobbies.status));
  assert.equal(new URL(hobbies.headers.get('location'), url).pathname, '/login');
  const dashboard = await get('/dev/dashboard');
  assert.equal(dashboard.status, 404);
  return { host: url.origin, status: 'passed', checked_at: new Date().toISOString(),
    checks: ['HTTPS', 'database readiness', 'production label', 'no simulation banner or demo codes', 'authentication gate', 'no dev dashboard'],
    real_world_operation: 'not established by these read-only checks' };
}
if (require.main === module) inspect(process.argv[2]).then((r) => console.log(JSON.stringify(r, null, 2))).catch((e) => { console.error(e.message); process.exitCode = 1; });
module.exports = { inspect };
