const { test, expect } = require('@playwright/test');
const { Pool } = require('pg');
const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const { sms, appContainer, rpc } = require('./runtime.cjs');

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

async function login(page, phone, { entry = '/login', destination = '/explore', screenshot } = {}) {
  await page.goto(entry);
  await expect(page).toHaveURL('http://localhost:4000/login');
  await connected(page);
  await expect(page.locator('#login-introduction')).toBeVisible();
  if (screenshot) await page.screenshot({ path: screenshot, fullPage: true, animations: 'disabled' });
  await page.locator('input[name=phone]').fill(phone);
  await page.getByRole('button', { name: 'Send code', exact: true }).click();
  await expect(page.locator('input[name=code]')).toBeVisible();
  await expect(page.getByText(/demo code:/)).toHaveCount(0);
  const mailbox = await sms(`/mailbox?phone=${encodeURIComponent(phone)}`);
  expect(mailbox.messages.length).toBeGreaterThan(0);
  const code = mailbox.messages.at(-1).body.match(/\b[0-9]{6}\b/)[0];
  await page.locator('input[name=code]').fill(code);
  await page.getByRole('button', { name: 'Verify', exact: true }).click();
  await expect(page).toHaveURL(`http://localhost:4000${destination}`);
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
  await form.locator('[name="session[category]"]').selectOption(hobby === 'guitar' ? 'music' : 'sport');
  await form.locator('[name="session[kind]"]').selectOption('event');
  await page.locator('#create-session').click();
  await expect(page).toHaveURL(/\/hobbies\/\d+$/);
  await connected(page);
  return { id: Number(new URL(page.url()).pathname.split('/').pop()), startsAt };
}

test.afterAll(async () => pool.end());

test('same release: SMS, Explore, equipment, referee, reconnect and restart', async ({ browser }, info) => {
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
    if (suffix === '1') {
      const seed = () => rpc('IO.puts("SPONTAAN_SETTING:" <> Jason.encode!(Fu.Simulation.seed!()))')
        .split('\n').find((line) => line.startsWith('SPONTAAN_SETTING:'));
      const initial = seed();
      expect(seed()).toBe(initial);
      const setting = JSON.parse(initial.slice('SPONTAAN_SETTING:'.length));
      expect(setting.sessions).toHaveLength(6);
      expect(setting.players).toHaveLength(12);
    }
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
    // Failed delivery must retain the requested page across the later successful login.
    await login(host, `+3168000010${suffix}`, {
      destination: '/hobbies', screenshot: info.outputPath(`${info.project.name}-login.png`),
    });
    const hobby = suffix === '1' ? 'futsal' : 'guitar';
    await host.goto('/profile');
    await connected(host);
    const experience = host.locator('#experience-form');
    const colours = new Set();
    for (const theme of ['spontaan', 'football', 'court', 'music', 'outdoors', 'making']) {
      await experience.locator('[name="experience[main_hobby]"]').fill(hobby);
      await experience.locator('[name="experience[experience_theme]"]').selectOption(theme);
      await experience.getByRole('button', { name: 'Save experience', exact: true }).click();
      await expect(host.locator('#spontaan-shell')).toHaveAttribute('data-experience', theme);
      colours.add(await host.locator('#spontaan-shell').evaluate((el) => getComputedStyle(el).getPropertyValue('--fu-accent').trim()));
    }
    expect(colours.size).toBe(6);
    await experience.locator('[name="experience[experience_theme]"]').selectOption('auto');
    await experience.getByRole('button', { name: 'Save experience', exact: true }).click();
    const selectedTheme = suffix === '1' ? 'football' : 'music';
    await expect(host.locator('#spontaan-shell')).toHaveAttribute('data-experience', selectedTheme);
    await host.goto('/explore');
    await connected(host);
    await expect(host.locator('#spontaan-shell')).toHaveAttribute('data-experience', selectedTheme);
    await expect(host.locator('#spontaan-brand')).toContainText('spontaan');
    await expect(host.locator('#explore-events')).toContainText('Commons six-a-side');
    await expect(host.locator('#main-hobby-link')).toHaveAttribute('href', `/explore?hobby=${hobby}`);
    await host.screenshot({ path: info.outputPath(`${info.project.name}-spontaan-${selectedTheme}.png`), fullPage: true, animations: 'disabled' });
    const title = `QA ${info.project.name} ${hobby}`;
    const { id, startsAt } = await create(host, title, hobby, 'committed');
    await expect(host.locator('#access-pending')).toBeVisible();

    const invitation = `/hobbies/${id}?from=invitation`;
    await login(guest, `+3168000020${suffix}`, { entry: invitation, destination: invitation });
    await expect(guest.locator('#join-session')).toBeVisible();
    await expect(guest.locator('#football-rank')).toHaveCount(0);

    await guest.goto('/explore');
    await connected(guest);
    await expect(guest.locator('#football-rank')).toHaveCount(0);
    await guest.locator('[name="filter[q]"]').fill(title);
    await expect(guest).toHaveURL(/q=QA/);
    await guest.locator('[name="filter[kind]"]').selectOption('event');
    await expect(guest.locator(`#explore-event-${id}`)).toBeVisible();
    await guest.reload();
    await connected(guest);
    await expect(guest.locator('[name="filter[q]"]')).toHaveValue(title);
    await guest.screenshot({ path: info.outputPath(`${info.project.name}-explore.png`), fullPage: true, animations: 'disabled' });
    await guest.getByRole('link', { name: title, exact: true }).click();
    await connected(guest);
    await expect(guest.locator('#host-controls')).toHaveCount(0);
    await guest.locator('#join-session').click();
    await guest.locator('#commit-session').click();
    await expect(host.locator('#hobby-participants')).toContainText('committed');

    await host.goto('/equipment');
    await connected(host);
    const gearName = `QA ${info.project.name} gear`;
    const tag = `qa-tag-${suffix}`;
    await host.locator('[name="asset[name]"]').fill(gearName);
    await host.locator('[name="asset[home_zone]"]').fill('QA shelf');
    await host.locator('[name="asset[beacon_id]"]').fill(tag);
    await host.locator('#equipment-form button').click();
    const gear = host.locator('article[id^="equipment-"]').filter({ has: host.getByRole('heading', { name: gearName, exact: true }) });
    await expect(gear).toBeVisible();
    const assetId = Number((await gear.getAttribute('id')).replace('equipment-', ''));
    await gear.locator('[name="location[zone]"]').fill('QA manual shelf');
    await gear.getByRole('button', { name: 'Save manual location', exact: true }).click();
    await expect(gear.locator('[data-source="manual"]')).toContainText('QA manual shelf');
    await gear.locator('[name="allocation[session_id]"]').selectOption(String(id));
    await gear.getByRole('button', { name: 'Reserve and share', exact: true }).click();
    await expect(gear.getByRole('link', { name: title, exact: true })).toBeVisible();
    await host.getByText('Connect a zone receiver', { exact: true }).click();
    await host.locator('[name="receiver[name]"]').fill(`QA receiver ${suffix}`);
    await host.locator('[name="receiver[zone]"]').fill('QA court');
    await host.locator('#receiver-form button').click();
    const token = await host.locator('#receiver-token code').innerText();
    expect(token).toMatch(/^fu-eq-/);
    await host.getByRole('button', { name: 'I saved it · hide', exact: true }).click();
    await expect(host.locator('#receiver-token')).toHaveCount(0);
    const report = { beacon_id: tag, message_id: `qa-${suffix}-sample`, observed_at: new Date().toISOString(), rssi: -55, zone: 'Forged zone', source: 'verified' };
    const ingest = (body, credential = token) => fetch('http://localhost:4000/api/equipment/observations', {
      method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${credential}` }, body: JSON.stringify(body),
    });
    expect((await ingest(report, 'invalid')).status).toBe(401);
    const first = await ingest(report);
    expect(first.status).toBe(200);
    const receipt = await first.json();
    expect(receipt.source).toBe('receiver_report');
    expect(receipt.zone).toBe('QA court');
    expect((await (await ingest(report)).json()).id).toBe(receipt.id);
    expect((await ingest({ ...report, rssi: -70 })).status).toBe(409);
    await expect(gear.locator('[data-source="receiver_report"]')).toContainText('QA court');
    await expect(gear.locator('[data-freshness="fresh"]')).toBeVisible();
    await host.screenshot({ path: info.outputPath(`${info.project.name}-equipment.png`), fullPage: true, animations: 'disabled' });
    if ((await host.locator('#receiver-settings').getAttribute('open')) === null) await host.locator('#receiver-settings summary').click();
    await host.getByRole('button', { name: 'Revoke credential', exact: true }).click();
    await expect(host.locator('#receiver-settings')).toContainText(`QA receiver ${suffix} · QA court · revoked`);
    expect((await ingest({ ...report, message_id: `qa-${suffix}-revoked` })).status).toBe(401);

    await host.goto(`/hobbies/${id}/assistant`);
    await connected(host);
    await host.getByText('Add a timer and scorekeeper', { exact: true }).click();
    const setup = host.locator('#configure-scorekeeper');
    await setup.locator('[name="board[team_a]"]').fill('Blue');
    await setup.locator('[name="board[team_b]"]').fill('Gold');
    await setup.locator('[name="board[duration_seconds]"]').fill('600');
    const referee = await setup.locator('[name="board[referee_id]"] option').last().getAttribute('value');
    await setup.locator('[name="board[referee_id]"]').selectOption(referee);
    await setup.locator('button').click();
    await expect(host.locator('#scoreboard')).toBeVisible();
    await guest.goto(`/hobbies/${id}/assistant`);
    await connected(guest);
    await expect(guest.locator('#event-equipment')).toContainText(gearName);
    await expect(guest.locator('#event-equipment [data-source="receiver_report"]')).toContainText('QA court');
    await expect(guest.locator('#referee-controls')).toBeVisible();
    await expect(guest.locator('#start-clock')).toHaveCount(0);
    await host.goto(`/hobbies/${id}`);
    await guest.goto(`/hobbies/${id}`);
    await connected(host);
    await connected(guest);

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

    await guest.goto(`/hobbies/${id}/assistant`);
    await host.goto(`/hobbies/${id}/assistant`);
    await connected(guest);
    await connected(host);
    await guest.locator('#start-clock').click();
    await expect(host.locator('#clock-status')).toHaveText('running');
    await guest.locator('#add-score-a').click();
    await expect(host.locator('#score-a')).toHaveText('1');
    await guest.locator('#add-score-b').click();
    await expect(host.locator('#score-b')).toHaveText('1');
    await expect(guest.locator('#score-b')).toHaveText('1');
    await guest.getByText('Correct a recorded score', { exact: true }).click();
    const correction = guest.locator('#correct-score-form');
    await correction.locator('[name="command[score_a]"]').fill('2');
    // A real update from the other screen must retain the open panel and local draft.
    await host.locator('#add-score-b').click();
    await expect(guest.locator('#score-b')).toHaveText('2');
    await expect(guest.locator('#score-correction')).toHaveAttribute('open', '');
    await expect(correction.locator('[name="command[score_a]"]')).toHaveValue('2');
    await correction.locator('[name="command[score_b]"]').fill('1');
    await correction.locator('[name="command[reason]"]').fill('QA correction reviewed by both sides');
    await correction.locator('button').click();
    await expect(host.locator('#score-a')).toHaveText('2');
    await guest.locator('#pause-clock').click();
    await expect(guest.locator('#clock-status')).toHaveText('paused');
    const paused = await guest.locator('#match-clock').innerText();
    const afterPause = Date.now() + 1200;
    await expect.poll(() => Date.now()).toBeGreaterThan(afterPause);
    await expect(guest.locator('#match-clock')).toHaveText(paused);
    await guest.locator('#start-clock').click();
    await expect(guest.locator('#clock-status')).toHaveText('running');
    const beforeRestart = (await pool.query('SELECT deadline_at FROM assistant_boards WHERE session_id = $1', [id])).rows[0];
    execFileSync('docker', ['restart', appContainer], { stdio: 'pipe', timeout: 30_000 });
    await expect.poll(async () => { try { return (await host.request.get('/healthz')).status(); } catch { return 0; } }).toBe(200);
    await guest.reload();
    await host.reload();
    await connected(guest);
    await connected(host);
    await expect(guest.locator('#score-a')).toHaveText('2');
    await expect(guest.locator('#score-b')).toHaveText('1');
    await expect(guest.locator('#clock-status')).toHaveText('running');
    const afterRestart = (await pool.query('SELECT deadline_at FROM assistant_boards WHERE session_id = $1', [id])).rows[0];
    expect(afterRestart.deadline_at).toEqual(beforeRestart.deadline_at);
    await guest.locator('#finalize-reason').fill('Both sides reviewed this synthetic score');
    await guest.locator('#finalize-score').click();
    await expect(host.locator('#result-finalized')).toBeVisible();
    await expect(host.locator('#assistant-history')).toContainText('QA correction reviewed by both sides');
    await host.screenshot({ path: info.outputPath(`${info.project.name}-assistant.png`), fullPage: true, animations: 'disabled' });
    await host.goto(`/hobbies/${id}`);
    await guest.goto(`/hobbies/${id}`);
    await connected(host);
    await connected(guest);
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
    await guest.screenshot({ path: screenshot, fullPage: true, animations: 'disabled' });
    await info.attach(`${info.project.name}-completed`, { path: screenshot, contentType: 'image/png' });

    await guest.goto(`/explore?scope=mine&q=${encodeURIComponent(title)}`);
    await connected(guest);
    await expect(guest.locator(`#explore-event-${id}`)).toContainText('completed');
    await guest.reload();
    await connected(guest);
    await expect(guest.locator(`#explore-event-${id}`)).toContainText('completed');

    const { id: cancelled } = await create(host, `QA ${info.project.name} cancellation`, 'table tennis', 'practice');
    await guest.goto(`/hobbies/${cancelled}`);
    await connected(guest);
    await guest.locator('#join-session').click();
    await expect(guest.locator('#leave-session-form')).toBeVisible();
    await host.locator('[name="cancel[reason]"]').fill('Synthetic room closure');
    await host.locator('#cancel-session-form button').click();
    await expect(guest.locator('#session-cancelled')).toContainText('Synthetic room closure');
    await expect(guest.locator('#join-session')).toHaveCount(0);
    await guest.goto('/profile');
    await connected(guest);
    await guest.getByRole('link', { name: 'Sign out', exact: true }).click();
    await expect(guest).toHaveURL(/\/login$/);
    await login(guest, `+3168000020${suffix}`);
    await guest.goto(`/explore?scope=mine&q=${encodeURIComponent(title)}`);
    await connected(guest);
    await expect(guest.locator(`#explore-event-${id}`)).toContainText('completed');
    fs.writeFileSync('/tmp/fu-rehearsal-browser-state.json', JSON.stringify({
      state: await guestContext.storageState(), sessionId: id, assetId,
    }), { mode: 0o600 });
    expect(errors).toEqual([]);
  } finally {
    await sms('/control', { mode: 'accepted' });
    await hostContext.close();
    await guestContext.close();
  }
});
