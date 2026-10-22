const { test } = require('node:test');
const assert = require('node:assert/strict');
const { inspect } = require('./live-preflight.cjs');
const headers = { 'x-fu-environment': 'production' };
const routes = {
  '/healthz': () => Response.json({ status: 'ok' }, { headers }),
  '/login': () => new Response('<form>Phone login</form>', { headers }),
  '/hobbies': () => new Response('', { status: 302, headers: { location: '/login' } }),
  '/dev/dashboard': () => new Response('', { status: 404 }),
};
test('read-only production checks pass without requesting an OTP', async () => {
  const visited = [];
  const result = await inspect('https://fu.example/', async (url, options) => {
    assert.equal(options.redirect, 'manual');
    visited.push(url.pathname);
    return routes[url.pathname]();
  });
  assert.equal(result.status, 'passed');
  assert.deepEqual(visited, Object.keys(routes));
});
test('rehearsal hosts and public hobby routes cannot pass live preflight', async () => {
  await assert.rejects(inspect('http://localhost/'), /HTTPS/);
  await assert.rejects(inspect('https://fu.example/', async () => Response.json({ status: 'ok' }, { headers: { 'x-fu-environment': 'rehearsal' } })));
  await assert.rejects(inspect('https://fu.example/', async (url) => url.pathname === '/hobbies' ? new Response('public') : routes[url.pathname]()));
});
