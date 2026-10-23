const { defineConfig, devices } = require('@playwright/test');

module.exports = defineConfig({
  testDir: '.',
  testMatch: 'pilot.spec.cjs',
  workers: 1,
  retries: 0,
  timeout: 150_000,
  globalTimeout: 7 * 60_000,
  expect: { timeout: 15_000 },
  reporter: [['list'], ['json', { outputFile: 'results/browser.json' }]],
  use: { baseURL: 'http://localhost:4000', trace: 'retain-on-failure' },
  projects: [
    { name: 'desktop', use: { viewport: { width: 1280, height: 900 } } },
    { name: 'mobile', use: { ...devices['Pixel 7'] } },
  ],
});
