const http = require('node:http');
const { timingSafeEqual, randomUUID } = require('node:crypto');

function createSimulator({ token }) {
  if (!token?.startsWith('fu-sim-')) throw new Error('Only simulation credentials are accepted');
  const messages = [];
  const stats = { accepted: 0, rejected: 0, requests: 0 };
  let mode = 'accepted';
  const json = (res, status, value) => { res.writeHead(status, { 'content-type': 'application/json', 'cache-control': 'no-store' }); res.end(JSON.stringify(value)); };
  return http.createServer(async (req, res) => {
    const url = new URL(req.url, 'http://sms');
    if (url.pathname === '/healthz') return json(res, 200, { status: 'ok', environment: 'rehearsal' });
    const given = Buffer.from(req.headers.authorization || '');
    const expected = Buffer.from(`AccessKey ${token}`);
    if (given.length !== expected.length || !timingSafeEqual(given, expected)) return json(res, 401, { error: 'unauthorized' });
    let body = '';
    try {
      for await (const chunk of req) {
        body += chunk;
        if (Buffer.byteLength(body) > 4096) return json(res, 413, { error: 'too_large' });
      }
      if (url.pathname === '/mailbox' && req.method === 'GET') {
        return json(res, 200, { messages: messages.filter((m) => m.phone === url.searchParams.get('phone')), stats, environment: 'rehearsal' });
      }
      if (url.pathname === '/stats') return json(res, 200, { ...stats, environment: 'rehearsal' });
      if (url.pathname === '/control' && req.method === 'POST') {
        const change = JSON.parse(body);
        if (!['accepted', 'unavailable', 'malformed', 'unauthorized', 'throttled', 'timeout'].includes(change.mode)) return json(res, 400, { error: 'invalid_mode' });
        mode = change.mode;
        return json(res, 200, { mode, environment: 'rehearsal' });
      }
      if (url.pathname !== '/messages' || req.method !== 'POST') return json(res, 404, { error: 'not_found' });
      stats.requests++;
      if (mode === 'timeout') {
        stats.rejected++;
        const timer = setTimeout(() => { if (!res.destroyed) json(res, 503, { error: 'late' }); }, 3000);
        res.on('close', () => clearTimeout(timer));
        return;
      }
      if (mode !== 'accepted') {
        stats.rejected++;
        if (mode === 'malformed') return json(res, 201, { unexpected: true });
        return json(res, { unavailable: 503, unauthorized: 401, throttled: 429 }[mode], { errors: [{ description: 'Synthetic provider failure' }] });
      }
      const form = new URLSearchParams(body);
      if (!form.get('body') || !form.get('originator') || !/^\+[1-9]\d{6,14}$/.test(form.get('recipients') || '')) return json(res, 400, { error: 'invalid_message' });
      const id = `sim-${randomUUID()}`;
      messages.push({ id, phone: form.get('recipients'), body: form.get('body'), accepted_at: new Date().toISOString(), simulated: true });
      stats.accepted++;
      return json(res, 201, { id, recipients: { totalCount: 1, totalSentCount: 1 }, simulated: true });
    } catch { return json(res, 400, { error: 'invalid_request' }); }
  });
}

if (require.main === module) {
  const server = createSimulator({ token: process.env.FU_SMS_API_KEY });
  server.listen(Number(process.env.PORT || 9166), '0.0.0.0', () => console.log('FU rehearsal SMS emulator ready'));
  process.on('SIGTERM', () => server.close(() => process.exit(0)));
}
module.exports = { createSimulator };
