// e2e/tests/auth-redirects.spec.ts
import { test, expect } from '@playwright/test';

test.describe('Authentication Redirects', () => {
  test('unauthenticated user visiting /upgrade redirects to root', async ({ page }) => {
    await page.goto('/upgrade');
    await expect(page).toHaveURL('/');
  });

  test('unauthenticated user visiting /billing redirects to root', async ({ page }) => {
    await page.goto('/billing');
    await expect(page).toHaveURL('/');
  });

  test('unauthenticated user visiting /episodes redirects to root', async ({ page }) => {
    await page.goto('/episodes');
    await expect(page).toHaveURL('/');
  });

  test('unauthenticated user visiting /settings redirects to root', async ({ page }) => {
    await page.goto('/settings');
    await expect(page).toHaveURL('/');
  });

  test('unauthenticated user can access landing page', async ({ page }) => {
    await page.goto('/');
    await expect(page).toHaveURL('/');
    await expect(page.locator('h1')).toContainText('Finally listen to your reading list');
  });

  test('unauthenticated user can access pricing section', async ({ page }) => {
    await page.goto('/#pricing');
    await expect(page.locator('h2:has-text("Pricing")')).toBeVisible();
  });
});
