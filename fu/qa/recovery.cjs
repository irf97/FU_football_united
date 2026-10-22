const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const { Pool } = require('pg');

if (process.env.FU_BROWSER_QA !== '1' ||
    new URL(process.env.DATABASE_URL).pathname !== '/fu_pilot_qa' ||
    !process.env.FU_QA_POSTGRES_CONTAINER) {
  throw new Error('Recovery QA requires the disposable database and its PostgreSQL container');
}
const original = new Pool({ connectionString: process.env.DATABASE_URL });
const restoredURL = new URL(process.env.DATABASE_URL);
restoredURL.pathname = '/fu_pilot_restored_qa';
const restored = new Pool({ connectionString: restoredURL.toString() });
const pgContainer = process.env.FU_QA_POSTGRES_CONTAINER;
const pgExec = (...args) => execFileSync('docker', ['exec', pgContainer, ...args], { stdio: 'pipe', timeout: 30_000 });

async function snapshot(pool) {
  const result = {};
  for (const table of ['players', 'otp_codes', 'hobby_sessions', 'hobby_participants', 'hobby_events']) {
    result[table] = (await pool.query(`SELECT * FROM ${table} ORDER BY id`)).rows;
  }
  return result;
}

async function waitReady(status) {
  for (let attempt = 0; attempt < 30; attempt++) {
    try {
      const response = await fetch('http://localhost:4000/healthz', { signal: AbortSignal.timeout(3000) });
      if (response.status === status) {
        assert.deepEqual(await response.json(), { status: status === 200 ? 'ok' : 'unavailable' });
        return;
      }
    } catch { /* A reconnecting DB is expected during this drill. */ }
    await new Promise((resolve) => setTimeout(resolve, 1000));
  }
  throw new Error(`Readiness did not reach ${status}`);
}

(async () => {
  try {
    const before = await snapshot(original);
    assert.equal(before.hobby_sessions.filter((s) => s.status === 'completed').length, 2);
    assert.equal(before.hobby_sessions.filter((s) => s.status === 'cancelled').length, 2);
    const backup = pgExec('pg_dump', '-U', 'postgres', '-Fc', 'fu_pilot_qa');
    pgExec('createdb', '-U', 'postgres', 'fu_pilot_restored_qa');
    execFileSync('docker', ['exec', '-i', pgContainer, 'pg_restore', '-U', 'postgres', '-d', 'fu_pilot_restored_qa'], {
      input: backup, stdio: ['pipe', 'pipe', 'pipe'], timeout: 30_000,
    });
    assert.deepEqual(await snapshot(restored), before);
    console.log('Backup restore: all identity, OTP and hobby records match');
    await original.end();
    await restored.end();
    execFileSync('docker', ['stop', pgContainer], { stdio: 'pipe', timeout: 30_000 });
    await waitReady(503);
    execFileSync('docker', ['start', pgContainer], { stdio: 'pipe', timeout: 30_000 });
    await waitReady(200);
    console.log('Database outage: readiness returned 503, then recovered to 200');
  } finally {
    await original.end().catch(() => {});
    await restored.end().catch(() => {});
  }
})().catch((error) => { console.error(error.message); process.exitCode = 1; });
