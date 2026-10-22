const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { Pool } = require('pg');
const { appContainer, docker, rpc, rpcAsync, pause, waitReady, percentile, save } = require('./runtime.cjs');
const envelope = require('./envelope.json');
const pool = new Pool({ connectionString: process.env.DATABASE_URL, max: 4 });
const readJSON = (file) => JSON.parse(docker('exec', appContainer, 'cat', `/tmp/${file}`).toString());

async function missions() {
  for (const file of ['missions.exs', 'envelope.json']) docker('cp', path.join(__dirname, file), `${appContainer}:/tmp/fu-${file}`);
  await rpcAsync('Code.eval_file("/tmp/fu-missions.exs"); Fu.QA.Missions.run(Jason.decode!(File.read!("/tmp/fu-envelope.json")))');
  const result = readJSON('fu-missions.json');
  result.context_p95_ms = percentile(result.context_latencies_ms);
  assert.ok(result.context_p95_ms <= envelope.context_p95_limit_ms, 'Mission mutation p95 exceeds the envelope');
  save('missions.json', result);
  return result;
}

async function interruptedTransaction(mission) {
  const blocker = await pool.connect();
  const id = mission.atomic_session_id;
  const player = mission.atomic_player_id;
  let blockedRPC;
  const started = performance.now();
  try {
    await blocker.query('BEGIN');
    // Block the event INSERT after join has already inserted its uncommitted membership.
    await blocker.query('LOCK TABLE hobby_events IN SHARE MODE');
    blockedRPC = rpcAsync(`Fu.Hobbies.join(${id}, Fu.Accounts.get_player!(${player}))`).then(() => null, (error) => error);
    let waiting = false;
    for (let attempt = 0; attempt < 50; attempt++) {
      const pending = await pool.query("SELECT count(*)::int AS count FROM pg_stat_activity WHERE datname='fu_pilot_qa' AND wait_event_type='Lock' AND query ILIKE '%insert%hobby_events%'");
      if (pending.rows[0].count > 0) { waiting = true; break; }
      await pause(100);
    }
    assert.ok(waiting, 'The history INSERT must actually be blocked after the membership write');
    docker('kill', '--signal=KILL', appContainer);
    await blocker.query('ROLLBACK');
    assert.ok(await blockedRPC, 'The interrupted caller must fail');
    const count = async (table, actorColumn) => (await pool.query(
      `SELECT count(*)::int AS count FROM ${table} WHERE session_id=$1 AND ${actorColumn}=$2`, [id, player],
    )).rows[0].count;
    assert.equal(await count('hobby_participants', 'player_id'), 0);
    assert.equal(await count('hobby_events', 'actor_id'), 0);
    const restart = performance.now();
    docker('start', appContainer);
    await waitReady();
    const recovery_ms = Math.round(performance.now() - restart);
    assert.ok(recovery_ms <= envelope.recovery_limit_seconds * 1000);
    rpc(`{:ok, _} = Fu.Hobbies.join(${id}, Fu.Accounts.get_player!(${player})); {:ok, _} = Fu.Hobbies.join(${id}, Fu.Accounts.get_player!(${player}))`);
    assert.equal(await count('hobby_participants', 'player_id'), 1);
    assert.equal(await count('hobby_events', 'actor_id'), 1);
    const result = { status: 'passed', observed_blocked_event_insert: true, partial_records: 0,
      membership_after_retry: 1, events_after_retry: 1, recovery_ms, elapsed_ms: Math.round(performance.now() - started) };
    save('interruption.json', result);
    return result;
  } finally {
    await blocker.query('ROLLBACK').catch(() => {});
    blocker.release();
    if (blockedRPC) await blockedRPC;
  }
}

async function sustainedReads() {
  // Both domain reads and authenticated HTTP rendering use the actual release and DB.
  docker('cp', path.join(__dirname, 'missions.exs'), `${appContainer}:/tmp/fu-missions.exs`);
  docker('cp', path.join(__dirname, 'envelope.json'), `${appContainer}:/tmp/fu-envelope.json`);
  const contextRun = rpcAsync('Code.eval_file("/tmp/fu-missions.exs"); Fu.QA.Missions.reads(Jason.decode!(File.read!("/tmp/fu-envelope.json")))');
  const auth = JSON.parse(fs.readFileSync('/tmp/fu-rehearsal-browser-state.json'));
  const cookie = auth.state.cookies.map((c) => `${c.name}=${c.value}`).join('; ');
  const start = performance.now();
  const deadline = start + envelope.soak_seconds * 1000;
  const latencies = [];
  const failures = [];
  await Promise.all(Array.from({ length: envelope.readers }, async (_, reader) => {
    let requests = 0;
    while (performance.now() < deadline) {
      const t = performance.now();
      try {
        const route = requests++ % 2 ? '/hobbies' : `/hobbies/${auth.sessionId}`;
        const response = await fetch(`http://localhost:4000${route}`, {
          headers: { cookie }, redirect: 'manual', signal: AbortSignal.timeout(5000),
        });
        assert.equal(response.status, 200);
        assert.equal(response.headers.get('x-fu-environment'), 'rehearsal');
        assert.ok((await response.text()).includes('simulation-banner'));
        latencies.push(performance.now() - t);
      } catch (error) { failures.push({ reader, message: error.message }); }
      await pause(envelope.read_pacing_ms);
    }
  }));
  await contextRun;
  const domain = readJSON('fu-reads.json');
  const result = {
    status: failures.length ? 'failed' : 'passed', duration_ms: Math.round(performance.now() - start),
    http_readers: envelope.readers, context_readers: envelope.readers,
    http_requests: latencies.length, context_requests: domain.latencies_ms.length,
    http_p95_ms: percentile(latencies), context_p95_ms: percentile(domain.latencies_ms), failures,
    http_latencies_ms: latencies, context_latencies_ms: domain.latencies_ms,
  };
  save('sustained-reads.json', result);
  assert.deepEqual(failures, []);
  assert.ok(latencies.length >= envelope.readers * 10, 'A substantial number of successful reads is required');
  assert.ok(result.http_p95_ms <= envelope.http_p95_limit_ms);
  assert.ok(result.context_p95_ms <= envelope.context_p95_limit_ms);
  const inspect = JSON.parse(docker('inspect', appContainer))[0];
  assert.equal(inspect.HostConfig.Memory, envelope.app_memory_limit_mib * 1024 * 1024);
  assert.equal(inspect.HostConfig.NanoCpus, envelope.app_cpus * 1e9);
  save('resources.json', { status: 'passed', image_id: inspect.Image,
    memory_limit_mib: inspect.HostConfig.Memory / 1024 / 1024, cpus: inspect.HostConfig.NanoCpus / 1e9,
    note: 'Enforced container limits; this is not a capacity guarantee beyond the measured envelope.' });
  return result;
}

(async () => {
  try {
    const mission = await missions();
    console.log(`Missions: ${mission.participants} synthetic participants, ${mission.sessions} sessions, p95 ${mission.context_p95_ms.toFixed(1)} ms`);
    const interruption = await interruptedTransaction(mission);
    console.log(`Interrupted transaction: no partial records; retry exactly once; recovery ${interruption.recovery_ms} ms`);
    const soak = await sustainedReads();
    console.log(`Sustained reads: ${soak.http_requests} HTTP / ${soak.context_requests} context reads; HTTP p95 ${soak.http_p95_ms.toFixed(1)} ms`);
  } finally { await pool.end(); }
})().catch((error) => { save('operations-error.json', { status: 'failed', message: error.message }); console.error(error); process.exitCode = 1; });
