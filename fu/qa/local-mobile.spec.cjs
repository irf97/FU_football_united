const { test, expect } = require('@playwright/test');
const { execFileSync } = require('node:child_process');
const path = require('node:path');
const http = require('node:http');
const { randomBytes } = require('node:crypto');
if (process.env.FU_LOCAL_BROWSER_QA !== '1') throw new Error('This suite requires the isolated local mobile CI workspace');
const root = path.resolve(__dirname, '..');
const compose = ['compose', '--project-name', 'spontaan-local-mobile', '--env-file', path.join(root, '.env.local-mobile'), '-f', path.join(root, 'compose.local-mobile.yml')];
function docker(args) { return execFileSync('docker', [...compose, ...args], { cwd: root, encoding: 'utf8', timeout: 300_000 }); }
async function connected(page) { await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/); }

async function foreignOriginStatus() {
  return new Promise((resolve, reject) => {
    const req = http.request('http://127.0.0.1:4030/live/websocket?vsn=2.0.0', {
      headers: { Connection: 'Upgrade', Upgrade: 'websocket', 'Sec-WebSocket-Version': '13', 'Sec-WebSocket-Key': randomBytes(16).toString('base64'), Origin: 'http://unrelated.example' },
    });
    req.on('response', (res) => { res.resume(); resolve(res.statusCode); });
    req.on('upgrade', (res, socket) => { socket.destroy(); resolve(res.statusCode); });
    req.on('error', reject); req.setTimeout(10_000, () => req.destroy(new Error('Origin check timed out'))); req.end();
  });
}

test('local phone sign-in, discovery, activity creation and saved restart', async ({ page }, info) => {
  expect(await foreignOriginStatus()).toBe(403);
  const errors = []; page.on('pageerror', (e) => errors.push(e.message));
  await page.goto('/login'); await connected(page);
  await expect(page.getByText('Use a Commons identity.', { exact: false })).toBeVisible();
  await page.locator('input[name=phone]').fill(info.project.name === 'desktop' ? '+31680000601' : '+31680000602');
  await page.getByRole('button', { name: 'Send code', exact: true }).click();
  const code = page.locator('#login-local-code'); await expect(code).toContainText('Local code:');
  const otp = (await code.textContent()).match(/\b\d{6}\b/)[0];
  await page.locator('input[name=code]').fill(otp);
  await page.getByRole('button', { name: 'Verify', exact: true }).click();
  await expect(page).toHaveURL(/\/explore$/); await connected(page);
  await page.locator('[name="filter[q]"]').fill('I want to play ping pong');
  await expect(page.locator('#explore-search-summary')).toContainText('table tennis');
  const rally = page.locator('#explore-events article').filter({ hasText: 'One more rally' });
  await expect(rally).toBeVisible(); await rally.locator('summary').click();
  await expect(rally.locator('details')).toContainText('table tennis · hobby');
  await page.screenshot({ path: info.outputPath(`${info.project.name}-local-explore.png`), fullPage: true, animations: 'disabled' });

  await page.goto('/hobbies/new'); await connected(page);
  const title = `Local ${info.project.name} workshop`;
  const form = page.locator('#hobby-session-form');
  const at = Date.now() + 3_600_000;
  for (const [field, value] of Object.entries({ title, hobby: 'woodworking', place: 'Commons workshop', capacity: '4', min_participants: '1', starts_at: new Date(at).toISOString(), ends_at: new Date(at + 3_600_000).toISOString() })) {
    await form.locator(`[name="session[${field}]"]`).fill(value);
  }
  for (const [field, value] of Object.entries({ category: 'making', kind: 'class', mode: 'open' })) {
    await form.locator(`[name="session[${field}]"]`).selectOption(value);
  }
  await page.locator('#create-session').click(); await expect(page).toHaveURL(/\/hobbies\/\d+$/); await connected(page);
  const savedPath = new URL(page.url()).pathname;
  await expect(page.getByRole('heading', { name: title, exact: true })).toBeVisible();
  docker(['down']);
  docker(['up', '--detach', '--wait', '--wait-timeout', '240', 'app']);
  await page.goto(savedPath); await connected(page);
  await expect(page.getByRole('heading', { name: title, exact: true })).toBeVisible();
  await expect(page.locator('#host-controls')).toBeVisible();
  await page.screenshot({ path: info.outputPath(`${info.project.name}-local-saved-restart.png`), fullPage: true, animations: 'disabled' });
  expect(errors).toEqual([]);
});
