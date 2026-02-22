import { test, expect } from '@playwright/test';
import { signInAsNewUser } from './helpers/auth';

test.describe('Simulation Banner', () => {
  test('amber banner visible on dashboard when simulation mode active', async ({ page }) => {
    // 1. Sign in as a fresh user (redirects to /episodes)
    await signInAsNewUser(page, 'e2e-sim-banner');
    await expect(page).toHaveURL(/\/episodes/);

    // 2. Assert "Simulation Mode" text is visible
    const bannerText = page.locator('text=Simulation Mode');
    await expect(bannerText).toBeVisible({ timeout: 5_000 });

    // 3. Assert the amber background banner is present
    const banner = page.locator('.bg-amber-600');
    await expect(banner).toBeVisible();

    // 4. Assert "External services mocked" text is present
    await expect(page.locator('text=External services mocked')).toBeVisible();

    // 5. Screenshot
    await page.screenshot({ path: 'test-results/transitions/simulation-banner-dashboard.png', fullPage: false });
  });

  test('amber banner visible on marketing/landing page', async ({ page }) => {
    // 1. Go to landing page (no auth needed)
    await page.goto('/');

    // 2. Assert "Simulation Mode" text is visible
    const bannerText = page.locator('text=Simulation Mode');
    await expect(bannerText).toBeVisible({ timeout: 5_000 });

    // 3. Assert the amber background banner is present
    const banner = page.locator('.bg-amber-600');
    await expect(banner).toBeVisible();

    // 4. Screenshot
    await page.screenshot({ path: 'test-results/transitions/simulation-banner-landing.png', fullPage: false });
  });
});
