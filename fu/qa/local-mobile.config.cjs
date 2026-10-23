const { defineConfig, devices } = require('@playwright/test');
module.exports = defineConfig({
  testDir: '.', testMatch: 'local-mobile.spec.cjs', workers: 1, retries: 0,
  timeout: 240_000, expect: { timeout: 20_000 },
  reporter: [['list'], ['json', { outputFile: 'results/local-mobile-browser.json' }]],
  outputDir: 'local-mobile-results',
  use: { baseURL: 'http://127.0.0.1:4030', trace: 'retain-on-failure' },
  projects: [
    { name: 'desktop', use: { viewport: { width: 1280, height: 900 } } },
    { name: 'mobile', use: { ...devices['Pixel 7'] } },
  ],
});
