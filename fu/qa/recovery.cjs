const assert = require('node:assert/strict');
const fs = require('node:fs');
const { execFileSync } = require('node:child_process');
const { Pool } = require('pg');
const { chromium } = require('@playwright/test');
const { appContainer, docker, waitReady, save } = require('./runtime.cjs');
const envelope = require('./envelope.json');

assert.ok(process.env.FU_QA_POSTGRES_CONTAINER, 'A disposable PostgreSQL container is required');
const pgContainer = process.env.FU_QA_POSTGRES_CONTAINER;
const original = new Pool({ connectionString: process.env.DATABASE_URL });
const restoredURL = new URL(process.env.DATABASE_URL);
restoredURL.pathname = '/fu_pilot_restored_qa';
const restored = new Pool({ connectionString: restoredURL.toString() });
const pgExec = (...args) => docker('exec', pgContainer, ...args);

async function snapshot(pool) {
  const result = {};
  for (const table of ['players', 'otp_codes', 'hobby_sessions', 'hobby_participants', 'hobby_events',
    'equipment_assets', 'equipment_receivers', 'equipment_observations', 'equipment_reservations', 'assistant_boards', 'assistant_events']) {
    result[table] = (await pool.query(`SELECT * FROM ${table} ORDER BY id`)).rows;
  }
  result.sequences = (await pool.query("SELECT sequencename, last_value FROM pg_sequences WHERE schemaname='public' ORDER BY sequencename")).rows;
  return result;
}

function startCandidate(name, config, database, port) {
  const network = Object.keys(config.NetworkSettings.Networks)[0];
  const env = config.Config.Env.map((entry) => entry.startsWith('DATABASE_URL=')
    ? `DATABASE_URL=postgres://postgres:postgres@db:5432/${database}` : entry);
  docker('run', '--detach', '--name', name, '--network', network,
    '--memory', '512m', '--cpus', '1', '-p', `127.0.0.1:${port}:4000`,
    ...env.flatMap((entry) => ['-e', entry]), config.Image);
}

async function restoreDrill(config) {
  docker('stop', appContainer);
  const before = await snapshot(original);
  assert.ok(before.hobby_sessions.filter((s) => s.status === 'completed').length >= 29);
  assert.ok(before.hobby_sessions.filter((s) => s.status === 'cancelled').length >= 11);
  const started = performance.now();
  const backup = pgExec('pg_dump', '-U', 'postgres', '-Fc', 'fu_pilot_qa');
  pgExec('createdb', '-U', 'postgres', 'fu_pilot_restored_qa');
  execFileSync('docker', ['exec', '-i', pgContainer, 'pg_restore', '-U', 'postgres', '-d', 'fu_pilot_restored_qa'], {
    input: backup, stdio: ['pipe', 'pipe', 'pipe'], timeout: 45_000,
  });
  assert.deepEqual(await snapshot(restored), before);
  startCandidate('fu-restored-qa', config, 'fu_pilot_restored_qa', 4001);
  await waitReady(200, 4001);
  const auth = JSON.parse(fs.readFileSync('/tmp/fu-rehearsal-browser-state.json'));
  const browser = await chromium.launch({ headless: true });
  try {
    const context = await browser.newContext({ storageState: auth.state });
    const page = await context.newPage();
    const response = await page.goto(`http://localhost:4001/hobbies/${auth.sessionId}`);
    assert.equal(response.status(), 200);
    await page.locator('#session-completed').waitFor();
    await page.waitForFunction(() => document.querySelector('[data-phx-main]')?.classList.contains('phx-connected'));
    assert.ok((await page.locator('#hobby-history').innerText()).includes('completed'));
    await page.goto(`http://localhost:4001/hobbies/${auth.sessionId}/assistant`);
    await page.locator('#result-finalized').waitFor();
    assert.equal(await page.locator('#score-a').innerText(), '2');
    assert.equal(await page.locator('#score-b').innerText(), '1');
    assert.ok((await page.locator('#assistant-history').innerText()).includes('QA correction reviewed by both sides'));
    assert.equal(await page.locator(`#shared-equipment-${auth.assetId}`).getAttribute('data-source'), 'unknown');
    await page.screenshot({ path: require('node:path').join(__dirname, 'results', 'restored-history.png'), fullPage: true });
  } finally { await browser.close(); }
  const maxId = Math.max(...before.hobby_sessions.map((s) => s.id));
  const hostId = before.hobby_sessions[0].host_id;
  docker('exec', 'fu-restored-qa', '/app/bin/fu', 'rpc', `
    start = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)
    {:ok, session} = Fu.Hobbies.create_session(Fu.Accounts.get_player!(${hostId}), %{title: "Restored write probe", hobby: "rehearsal", mode: "open", place: "Synthetic room", starts_at: start, ends_at: DateTime.add(start, 3600, :second), capacity: 2, min_participants: 1})
    unless session.id > ${maxId}, do: raise("restored sequence did not advance")
  `);
  docker('rm', '-f', 'fu-restored-qa');
  docker('start', appContainer);
  await waitReady();
  const result = { status: 'passed', elapsed_ms: Math.round(performance.now() - started),
    checkpoint: 'quiescent', committed_record_loss: 0, compared_tables: Object.keys(before).filter((k) => k !== 'sequences'),
    row_counts: Object.fromEntries(Object.entries(before).map(([key, rows]) => [key, rows.length])),
    sequences_match: true, restored_authenticated_browser: true, restored_write: true, image_id: config.Image,
    limitation: 'Zero loss at this completed backup checkpoint; no production RPO or continuous backup claim.' };
  save('restore.json', result);
  return result;
}

async function outageDrill() {
  await original.end();
  await restored.end();
  docker('stop', pgContainer);
  const unavailable_ms = await waitReady(503);
  const start = performance.now();
  docker('start', pgContainer);
  await waitReady();
  const recovery_ms = Math.round(performance.now() - start);
  assert.ok(recovery_ms <= envelope.recovery_limit_seconds * 1000);
  const result = { status: 'passed', unavailable_status: 503, recovered_status: 200, unavailable_ms, recovery_ms };
  save('database-outage.json', result);
  return result;
}

async function configurationRollback(config) {
  docker('stop', appContainer);
  startCandidate('fu-bad-config-qa', config, 'fu_database_does_not_exist_qa', 4000);
  await waitReady(503);
  docker('rm', '-f', 'fu-bad-config-qa');
  const start = performance.now();
  docker('start', appContainer);
  await waitReady();
  const recovery_ms = Math.round(performance.now() - start);
  assert.ok(recovery_ms <= envelope.recovery_limit_seconds * 1000);
  const result = { status: 'passed', bad_candidate_status: 503, restored_status: 200, recovery_ms,
    known_good_image_id: config.Image, scope: 'Bad database configuration rejected; known-good image and configuration resumed. No code/schema version rollback claim.' };
  save('configuration-rollback.json', result);
  return result;
}

(async () => {
  try {
    const config = JSON.parse(docker('inspect', appContainer))[0];
    const restore = await restoreDrill(config);
    console.log(`Restore: all ${restore.compared_tables.length} table snapshots and sequences match; event, scorekeeper, sharing scope and new write verified (${restore.elapsed_ms} ms)`);
    const outage = await outageDrill();
    console.log(`Database outage: 503 to 200, recovered in ${outage.recovery_ms} ms`);
    const rollback = await configurationRollback(config);
    console.log(`Configuration rollback: rejected candidate, known-good release recovered in ${rollback.recovery_ms} ms`);
  } finally {
    for (const name of ['fu-restored-qa', 'fu-bad-config-qa']) {
      try { docker('rm', '-f', name); } catch { /* Candidate may already be removed. */ }
    }
    try { docker('start', pgContainer); docker('start', appContainer); } catch { /* Preserve the original failure. */ }
    await original.end().catch(() => {});
    await restored.end().catch(() => {});
  }
})().catch((error) => { save('recovery-error.json', { status: 'failed', message: error.message }); console.error(error); process.exitCode = 1; });
