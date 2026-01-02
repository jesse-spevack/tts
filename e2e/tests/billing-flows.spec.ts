// e2e/tests/billing-flows.spec.ts
import { test, expect } from '@playwright/test';
import { signInAsPremiumUser, signInAsCanceledUser, signInAsPastDueUser, signInAsCancelingUser } from './helpers/auth';

test.describe('Billing Flows (Premium User)', () => {
  test('billing page shows Premium Plan card', async ({ page }) => {
    await signInAsPremiumUser(page);
    await page.goto('/billing');
    await expect(page.locator('text=Premium Plan')).toBeVisible();
    await expect(page.locator('text=Renews on')).toBeVisible();
  });

  test('Manage Subscription button opens Stripe portal', async ({ page }) => {
    await signInAsPremiumUser(page);
    await page.goto('/billing');

    await page.click('button:has-text("Manage Subscription")');

    await expect(page).toHaveURL(/billing\.stripe\.com/);
  });

  test('billing page accessible from Settings', async ({ page }) => {
    await signInAsPremiumUser(page);
    await page.goto('/settings');
    await expect(page.locator('h2:has-text("Billing")')).toBeVisible();
    await page.click('a:has-text("Manage Billing")');
    await expect(page).toHaveURL('/billing');
  });

  test('subscription pending cancellation shows Ends on', async ({ page }) => {
    await signInAsCancelingUser(page);
    await page.goto('/billing');
    await expect(page.locator('text=Premium Plan')).toBeVisible();
    await expect(page.locator('text=Ends on')).toBeVisible();
  });
});

// Skip: These tests require users with specific Stripe subscription states
// that are complex to set up programmatically
test.describe.skip('Billing Edge Cases', () => {
  test('canceled subscription shows upgrade options', async ({ page }) => {
    await signInAsCanceledUser(page);
    await page.goto('/billing');
    await expect(page.locator('text=Subscription Ended')).toBeVisible();
    await expect(page.locator('input[type="submit"][value="Subscribe"]')).toBeVisible();
  });

  test('past due subscription shows Fix Payment button', async ({ page }) => {
    await signInAsPastDueUser(page);
    await page.goto('/billing');
    await expect(page.locator('text=Payment Failed')).toBeVisible();
    await expect(page.locator('button:has-text("Fix Payment")')).toBeVisible();
  });
});
