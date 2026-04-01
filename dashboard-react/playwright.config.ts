import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './tests/e2e',
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: 1,
  timeout: 60000, // 60s per test — fail fast instead of hanging
  reporter: [['html', { outputFolder: 'tests/report/playwright', open: 'never' }]],
  use: {
    baseURL: 'http://localhost:5173',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    viewport: { width: 1280, height: 720 },
    video: 'on-first-retry',
  },
  webServer: {
    command: 'npm run dev',
    url: 'http://localhost:5173',
    reuseExistingServer: true,
    timeout: 60000, // 60s — was 120s; start dev server first if it times out
  },
  projects: [
    // Use Firefox — avoids Chrome crashes during automation; run `npx playwright install firefox` if needed
    { name: 'firefox', use: { ...devices['Desktop Firefox'] } },
  ],
  snapshotPathTemplate: '{testDir}/__screenshots__/{testFileDir}/{testFileName}-snapshots/{arg}-{projectName}{ext}',
});
