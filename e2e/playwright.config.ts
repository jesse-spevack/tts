import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './tests',
  timeout: 120_000, // Simulation tests run long
  fullyParallel: false, // Run sequentially for Stripe state
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: 1,
  reporter: [['html', { open: 'never' }]],
  use: {
    baseURL: 'http://localhost:3000',
    headless: false,
    trace: 'retain-on-failure',
    screenshot: 'on',
    video: 'retain-on-failure',
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
  // Only auto-start the server in CI. Locally, boot it yourself:
  //   SIMULATE_EXTERNAL=true bin/dev
  ...(!process.env.CI ? {} : {
    webServer: {
      command: 'cd .. && bin/rails server -p 3000',
      url: 'http://localhost:3000',
      reuseExistingServer: false,
      timeout: 120 * 1000,
    },
  }),
});
