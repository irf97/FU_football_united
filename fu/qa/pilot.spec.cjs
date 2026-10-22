const { test, expect } = require('@playwright/test');
const { Pool } = require('pg');
const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const { sms, appContainer } = require('./runtime.cjs');

// This suite controls a disposable release and reads its synthetic OTP mailbox.
// Refuse to run against any other database or browser host.
if (process.env.FU_BROWSER_QA !== '1' ||
    new URL(process.env.DATABASE_URL).pathname !== '/fu_pilot_qa') {
  throw new Error('Pilot QA requires FU_BROWSER_QA=1 and the disposable fu_pilot_qa database');
}
const pool = new Pool({ connectionString: process.env.DATABASE_URL, max: 3 });

async function connected(page) {
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
}

async function login(page, phone) {
  await page.goto('/login');
  await connected(page);
  await page.locator('input[name=phone]').fill(phone);
  await page.getByRole('button', { name: 'Send code', exact: true }).click();
  await expect(page.locator('input[name=code]')).toBeVisible();
  await expect(page.getByText(/demo code:/)).toHaveCount(0);
  const mailbox = await sms(`/mailbox?phone=${encodeURIComponent(phone)}`);
  expect(mailbox.messages).toHaveLength(1);
  const code = mailbox.messages[0].body.match(/\b[0-9]{6}\b/)[0];
  await page.locator('input[name=code]').fill(code);
  await page.getByRole('button', { name: 'Verify', exact: true }).click();
  await expect(page).toHaveURL('http://localhost:4000/');
  await connected(page);
}

async function create(page, title, hobby, mode) {
  await page.goto('/hobbies/new');
  await connected(page);
  const form = page.locator('#hobby-session-form');
  const startsAt = Date.now() + 15_000;
  for (const [field, value] of Object.entries({
    title, hobby, place: 'Synthetic QA room', capacity: '2', min_participants: '1',
    starts_at: new Date(startsAt).toISOString(),
    ends_at: new Date(Date.now() + 3_600_000).toISOString(),
  })) await form.locator(`[name="session[${field}]"]`).fill(value);
  await form.locator('[name="session[mode]"]').selectOption(mode);
  await page.locator('#create-session').click();
  await expect(page).toHaveURL(/\/hobbies\/\d+$/);
  await connected(page);
  return { id: Number(new URL(page.url()).pathname.split('/').pop()), startsAt };
}

test.afterAll(async () => pool.end());

test('same release: SMS failures, shared session, reconnect and restart', async ({ browser }, info) => {
  const { viewport, userAgent, deviceScaleFactor, isMobile, hasTouch } = info.project.use;
  const options = { baseURL: "http://localhost:4000", viewport, userAgent, deviceScaleFactor, isMobile, hasTouch };
  const hostContext = await browser.newContext(options);
  const guestContext = await browser.newContext(options);
  let guestSocket;
  let transportDropped = false;
  await guestContext.routeWebSocket(/\/live\/websocket/, async (socket) => {
    if (transportDropped) {
      await socket.close({ code: 1013, reason: 'Synthetic QA outage' });
      return;
    }
    guestSocket = socket;
    socket.connectToServer(); // Forward every application message unchanged.
  });
  const host = await hostContext.newPage();
  const guest = await guestContext.newPage();
  const errors = [];
  for (const page of [host, guest]) {
    page.on('pageerror', (error) => errors.push(error.message));
    page.on('dialog', (dialog) => dialog.accept());
  }

  try {
    const suffix = info.project.name === 'desktop' ? '1' : '2';
    for (const [index, mode] of ['unavailable', 'malformed', 'unauthorized', 'throttled', 'timeout'].entries()) {
      await sms('/control', { mode });
      const before = await sms('/stats');
      await host.goto('/hobbies');
      await expect(host).toHaveURL(/\/login$/);
      await connected(host);
      await expect(host.locator('#simulation-banner')).toBeVisible();
      const phone = `+316800009${suffix}${index}`;
      await host.locator('input[name=phone]').fill(phone);
      await host.getByRole('button', { name: 'Send code', exact: true }).click();
      await expect(host.getByText("We couldn't send your code. Try again later.")).toBeVisible();
      await expect(host.locator('input[name=code]')).toHaveCount(0);
      await expect(host.getByText(/demo code:/)).toHaveCount(0);
      const after = await sms('/stats');
      expect(after.requests - before.requests).toBe(1); // No automatic POST retry.
      const codes = await pool.query('SELECT consumed_at FROM otp_codes WHERE phone = $1', [phone]);
      expect(codes.rows).toHaveLength(1);
      expect(codes.rows[0].consumed_at).not.toBeNull();
    }
    await sms('/control', { mode: 'accepted' });
    await login(host, `+3168000010${suffix}`);
    await login(guest, `+3168000020${suffix}`);
    const hobby = suffix === '1' ? 'futsal' : 'guitar';
    const title = `QA ${info.project.name} ${hobby}`;
    const { id, startsAt } = await create(host, title, hobby, 'committed');
    await expect(host.locator('#access-pending')).toBeVisible();

    await guest.goto('/hobbies');
    await connected(guest);
    await guest.locator('[name="filter[hobby]"]').fill(hobby);
    await guest.getByRole('link', { name: title, exact: true }).click();
    await connected(guest);
    await expect(guest.locator('#host-controls')).toHaveCount(0);
    await guest.locator('#join-session').click();
    await guest.locator('#commit-session').click();
    await expect(host.locator('#hobby-participants')).toContainText('committed');

    transportDropped = true;
    await guestContext.setOffline(true);
    // Chromium's offline emulation does not close an established WebSocket.
    // Close the real transport explicitly and reject retries during the outage.
    expect(guestSocket).toBeDefined();
    await guestSocket.close({ code: 1012, reason: 'Synthetic QA transport drop' });
    await expect(guest.locator('[data-phx-main]')).not.toHaveClass(/phx-connected/);
    await expect(guest.locator('[data-phx-main]')).toHaveClass(/phx-client-error/);
    await host.locator('[name="access[note]"]').fill('Synthetic operator confirmation');
    await host.locator('#confirm-access-form button').click();
    await expect(host.locator('#access-confirmed')).toBeVisible();
    await expect(guest.locator('#access-confirmed')).toHaveCount(0);
    transportDropped = false;
    await guestContext.setOffline(false);
    await connected(guest);
    await expect(guest.locator('#access-confirmed')).toBeVisible();

    // Wait for real wall-clock time; the rehearsal never edits application time.
    await expect.poll(() => Date.now(), { timeout: 20_000 }).toBeGreaterThanOrEqual(startsAt);
    await host.locator('#start-session').click();
    await expect(host.locator('#finish-session')).toBeVisible();
    await guest.locator('#attend-session').click();
    await expect(guest.locator('#attendance-recorded')).toBeVisible();
    await host.locator('#finish-session').click();
    await expect(guest.locator('#session-completed')).toBeVisible();
    await expect(host.locator('#session-completed')).toBeVisible();

    execFileSync('docker', ['restart', appContainer], { stdio: 'pipe', timeout: 30_000 });
    await expect.poll(async () => {
      try { return (await host.request.get('/healthz')).status(); }
      catch { return 0; }
    }).toBe(200);
    await guest.reload();
    await connected(guest);
    await expect(guest.locator('#session-completed')).toBeVisible();
    await expect(guest.locator('#hobby-history')).toContainText('completed');
    const persisted = await pool.query(
      'SELECT s.status, p.status AS participant_status FROM hobby_sessions s JOIN hobby_participants p ON p.session_id = s.id WHERE s.id = $1', [id],
    );
    expect(persisted.rows).toEqual([{ status: 'completed', participant_status: 'attended' }]);
    const screenshot = info.outputPath(`${info.project.name}-completed.png`);
    await guest.screenshot({ path: screenshot, fullPage: true });
    await info.attach(`${info.project.name}-completed`, { path: screenshot, contentType: 'image/png' });

    fs.writeFileSync('/tmp/fu-rehearsal-browser-state.json', JSON.stringify({
      state: await guestContext.storageState(), sessionId: id,
    }), { mode: 0o600 });

    const { id: cancelled } = await create(host, `QA ${info.project.name} cancellation`, 'table tennis', 'practice');
    await guest.goto(`/hobbies/${cancelled}`);
    await connected(guest);
    await guest.locator('#join-session').click();
    await expect(guest.locator('#leave-session-form')).toBeVisible();
    await host.locator('[name="cancel[reason]"]').fill('Synthetic room closure');
    await host.locator('#cancel-session-form button').click();
    await expect(guest.locator('#session-cancelled')).toContainText('Synthetic room closure');
    await expect(guest.locator('#join-session')).toHaveCount(0);
    expect(errors).toEqual([]);
  } finally {
    await sms('/control', { mode: 'accepted' });
    await hostContext.close();
    await guestContext.close();
  }
});
