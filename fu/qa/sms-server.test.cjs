const { test } = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const { createSimulator } = require('./sms-server.cjs');

test('provider emulator authenticates, delivers to a private mailbox and injects failures', async () => {
  const server = createSimulator({ token: 'fu-sim-test-only' });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const base = `http://127.0.0.1:${server.address().port}`;
  const auth = { authorization: 'AccessKey fu-sim-test-only' };
  const send = () => fetch(`${base}/messages`, { method: 'POST', headers: { ...auth, 'content-type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ originator: 'FU', recipients: '+31680000001', body: 'Your FU code is 123456' }) });
  try {
    assert.equal((await fetch(`${base}/mailbox?phone=%2B31680000001`)).status, 401);
    assert.equal((await send()).status, 201);
    const message = await fetch(`${base}/mailbox?phone=%2B31680000001`, { headers: auth }).then((r) => r.json());
    assert.equal(message.messages[0].body, 'Your FU code is 123456');
    await fetch(`${base}/control`, { method: 'POST', headers: { ...auth, 'content-type': 'application/json' }, body: JSON.stringify({ mode: 'unavailable' }) });
    assert.equal((await send()).status, 503);
    const after = await fetch(`${base}/mailbox?phone=%2B31680000001`, { headers: auth }).then((r) => r.json());
    assert.equal(after.messages.length, 1);
  } finally { await new Promise((resolve) => server.close(resolve)); }
});

test('simulator refuses credentials that could be a live account key', () => {
  assert.throws(() => createSimulator({ token: 'live-placeholder' }), /simulation/);
});
