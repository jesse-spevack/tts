// e2e/tests/upgrade-flows.spec.ts
import { test, expect } from '@playwright/test';
import { signInAsNewUser, signInAsPremiumUser } from './helpers/auth';

// Uses fresh test users for isolation. Clean up with: bin/rake test:purge_e2e_users
test.describe('Upgrade Flows (Free User)', () => {
  test('free user sees Upgrade link in header', async ({ page }) => {
    await signInAsNewUser(page, 'free');
    await expect(page.locator('a:has-text("Upgrade")').first()).toBeVisible();
  });

  test('clicking Upgrade goes to /upgrade page', async ({ page }) => {
    await signInAsNewUser(page, 'free');
    await page.locator('a:has-text("Upgrade")').first().click();
    await expect(page).toHaveURL('/upgrade');
  });

  test('/billing redirects free user to /upgrade', async ({ page }) => {
    await signInAsNewUser(page, 'free');
    await page.goto('/billing');
    await expect(page).toHaveURL('/upgrade');
  });

  test('upgrade page shows pricing toggle with annual default', async ({ page }) => {
    await signInAsNewUser(page, 'free');
    await page.goto('/upgrade');
    await expect(page.locator('input[value="annual"]')).toBeChecked();
    await expect(page.locator('input[value="monthly"]')).not.toBeChecked();
  });

  test('upgrade page toggle switches price display', async ({ page }) => {
    await signInAsNewUser(page, 'free');
    await page.goto('/upgrade');

    // Annual price visible by default
    await expect(page.locator('[data-pricing-toggle-target="annualPrice"]')).toBeVisible();
    await expect(page.locator('[data-pricing-toggle-target="monthlyPrice"]')).toBeHidden();

    // Toggle to monthly
    await page.click('label:has(input[value="monthly"])');

    // Monthly price visible
    await expect(page.locator('[data-pricing-toggle-target="monthlyPrice"]')).toBeVisible();
    await expect(page.locator('[data-pricing-toggle-target="annualPrice"]')).toBeHidden();
  });

  test('upgrade page shows free plan usage', async ({ page }) => {
    await signInAsNewUser(page, 'free');
    await page.goto('/upgrade');
    await expect(page.locator('text=Free Plan')).toBeVisible();
  });

  test('subscribe button redirects to Stripe checkout', async ({ page }) => {
    await signInAsNewUser(page, 'free');
    await page.goto('/upgrade');

    // Click subscribe - will redirect to Stripe
    await page.click('input[type="submit"][value="Subscribe"]');

    await expect(page).toHaveURL(/checkout\.stripe\.com/);
  });
});

test.describe('Premium User Redirects', () => {
  test('/upgrade redirects premium user to /billing', async ({ page }) => {
    await signInAsPremiumUser(page);
    await page.goto('/upgrade');
    await expect(page).toHaveURL('/billing');
  });

  test('premium user does not see Upgrade in header', async ({ page }) => {
    await signInAsPremiumUser(page);
    await expect(page.locator('a:has-text("Upgrade")')).not.toBeVisible();
  });
});
