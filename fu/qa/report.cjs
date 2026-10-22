const fs = require('node:fs');
const path = require('node:path');
const envelope = require('./envelope.json');
const directory = path.join(__dirname, 'results');
fs.mkdirSync(directory, { recursive: true });
const read = (name) => {
  try { return JSON.parse(fs.readFileSync(path.join(directory, name))); }
  catch { return null; }
};
const files = ['boundary', 'missions', 'interruption', 'sustained-reads', 'resources', 'restore', 'database-outage', 'configuration-rollback'];
const gates = Object.fromEntries(files.map((name) => [name, read(`${name}.json`) || { status: 'not_completed' }]));
const browser = read('browser.json');
gates.browser = { status: browser?.stats?.expected === 2 && browser.stats.unexpected === 0 && browser.stats.skipped === 0 ? 'passed' : 'not_passed',
  passed: browser?.stats?.expected || 0, failed: browser?.stats?.unexpected || 0, skipped: browser?.stats?.skipped || 0 };
const passed = process.env.FU_QA_EXIT === '0' && Object.values(gates).every((g) => g.status === 'passed');
const report = {
  title: envelope.name, status: passed ? 'passed_within_envelope' : 'incomplete_or_failed',
  completed_at: new Date().toISOString(), evidence_type: 'simulation', formal_trl9: false,
  manifest: read('manifest.json'), envelope, gates,
  real_world_evidence_pending: [
    'Deployment on the chosen persistent host, database and TLS domain.',
    'Real SMS account, handset receipt and single-use login on intended devices.',
    'Venue permission and consenting participants completing real sessions.',
    'Operational monitoring, provider budgets, incident ownership and retention controls.',
    'A restore drill in the intended environment, and observed operation over an agreed period.',
    'Requalification after material code, schema, topology or provider changes.',
  ],
};
fs.writeFileSync(path.join(directory, 'rehearsal-report.json'), JSON.stringify(report, null, 2));
const escape = (text) => String(text).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const metrics = [
  ['Synthetic mission participants', gates.missions.participants], ['Mission sessions', gates.missions.sessions],
  ['HTTP reads', gates['sustained-reads'].http_requests], ['HTTP p95 (ms)', gates['sustained-reads'].http_p95_ms?.toFixed(1)],
  ['Context read p95 (ms)', gates['sustained-reads'].context_p95_ms?.toFixed(1)],
  ['Interrupted transaction recovery (ms)', gates.interruption.recovery_ms],
  ['Database recovery (ms)', gates['database-outage'].recovery_ms],
  ['Loss at backup checkpoint', gates.restore.committed_record_loss],
];
fs.writeFileSync(path.join(directory, 'rehearsal-report.html'), `<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>FU rehearsal evidence</title>
<style>body{margin:0;background:#f5f1e9;color:#20241f;font:17px/1.55 system-ui,sans-serif}main{max-width:1000px;margin:auto;padding:48px 24px}h1{font-size:42px;line-height:1.1;margin:.3em 0}h2{font-size:23px;margin-top:2em}.eyebrow{letter-spacing:.15em;font-size:12px;font-weight:700}.status{padding:16px;background:${passed ? '#d9ead8' : '#f4ddc4'};border-radius:8px}table{border-collapse:collapse;width:100%;background:#fff9}th,td{text-align:left;padding:12px;border-bottom:1px solid #d9d8cd}code{overflow-wrap:anywhere}li{margin:.5em 0}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(210px,1fr));gap:16px}.metric{background:white;padding:16px;border-radius:8px}.metric strong{display:block;font-size:28px}.small{font-size:14px;color:#586052}</style>
<main><div class="eyebrow">FU / OPERATIONAL REHEARSAL</div><h1>Evidence within a measured envelope</h1><p class="status">${passed ? 'All rehearsal gates passed.' : 'Rehearsal incomplete or failed. Review the gate results.'} This is simulation evidence. Real TRL 9 is not established.</p>
<p class="small">Completed ${escape(report.completed_at)} · Revision <code>${escape(report.manifest?.source_revision || 'not recorded')}</code><br>Image <code>${escape(report.manifest?.image_id || 'not recorded')}</code></p>
<div class="grid">${metrics.map(([label, value]) => `<div class="metric">${escape(label)}<strong>${escape(value ?? 'Pending')}</strong></div>`).join('')}</div>
<h2>Gates</h2><table><thead><tr><th>Check</th><th>Observed result</th></tr></thead><tbody>${Object.entries(gates).map(([name, gate]) => `<tr><td>${escape(name)}</td><td>${escape(gate.status)}</td></tr>`).join('')}</tbody></table>
<h2>Operating envelope</h2><p>${envelope.synthetic_participants} mission participants, ${envelope.sessions_per_mode} sessions per mode, capacity ${envelope.session_capacity}; desktop and mobile Chromium; ${envelope.readers} authenticated HTTP readers plus ${envelope.readers} domain readers for ${envelope.soak_seconds} seconds on ${envelope.app_cpus} CPU / ${envelope.app_memory_limit_mib} MiB. HTTP p95 ≤ ${envelope.http_p95_limit_ms} ms, context p95 ≤ ${envelope.context_p95_limit_ms} ms; recovery ≤ ${envelope.recovery_limit_seconds} seconds. Two browser flows add four synthetic identities.</p>
<h2>Limits of this evidence</h2><ul>${envelope.limitations.map((s) => `<li>${escape(s)}</li>`).join('')}</ul>
<h2>Transfer to real conditions</h2><ol>${report.real_world_evidence_pending.map((s) => `<li>${escape(s)}</li>`).join('')}</ol><p class="small">The same Phoenix image supports both modes. See DEPLOY.md for runtime configuration and the live preflight command. Raw measurements and gates accompany this report as JSON.</p></main></html>`);
console.log(`Rehearsal report: ${report.status}`);
if (!passed) process.exitCode = 1;
