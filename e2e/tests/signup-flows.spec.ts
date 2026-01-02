// e2e/tests/signup-flows.spec.ts
import { test, expect } from '@playwright/test';

test.describe('Landing Page Signup Flows', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
  });

  test('free signup opens modal with correct heading', async ({ page }) => {
    // Click "Start listening free" button
    await page.click('button[data-plan="free"]');

    // Verify modal opens with correct content
    const modal = page.locator('dialog[open]');
    await expect(modal).toBeVisible();
    await expect(modal.locator('h3')).toContainText('Start listening free');
    await expect(modal.locator('text=2 episodes/month')).toBeVisible();
  });

  test('premium annual signup opens modal', async ({ page }) => {
    // Scroll to pricing section
    await page.goto('/#pricing');

    // Verify annual is selected by default
    await expect(page.locator('input[value="annual"]')).toBeChecked();

    // Click "Get Premium" button
    await page.click('button[data-pricing-toggle-target="premiumLink"]');

    // Verify modal opens
    const modal = page.locator('dialog[open]');
    await expect(modal).toBeVisible();
  });

  test('premium monthly signup opens modal after toggle', async ({ page }) => {
    // Scroll to pricing section
    await page.goto('/#pricing');

    // Toggle to monthly by clicking the label
    await page.click('label:has(input[value="monthly"])');

    // Click "Get Premium" button
    await page.click('button[data-pricing-toggle-target="premiumLink"]');

    // Verify modal opens
    const modal = page.locator('dialog[open]');
    await expect(modal).toBeVisible();

    // Verify the button has monthly plan data
    const premiumButton = page.locator('button[data-pricing-toggle-target="premiumLink"]');
    await expect(premiumButton).toHaveAttribute('data-plan', 'premium_monthly');
  });

  test('modal can be closed by clicking backdrop', async ({ page }) => {
    await page.click('button[data-plan="free"]');

    const modal = page.locator('dialog[open]');
    await expect(modal).toBeVisible();

    // Click outside modal (on backdrop)
    await page.click('dialog[open]', { position: { x: 10, y: 10 } });
    await expect(modal).not.toBeVisible();
  });

  test('email validation shows error for invalid email', async ({ page }) => {
    await page.click('button[data-plan="free"]');

    // Fill with invalid email
    await page.fill('input[type="email"]', 'not-an-email');

    // Click the submit input
    await page.click('input[type="submit"]');

    // Browser validation should prevent submission
    const emailInput = page.locator('input[type="email"]');
    await expect(emailInput).toBeFocused();
  });

  test('signup form submits and shows confirmation', async ({ page }) => {
    await page.click('button[data-plan="free"]');

    await page.fill('input[type="email"]', 'test-e2e@example.com');
    await page.click('input[type="submit"]');

    // Should show confirmation message
    await expect(page.locator('text=Check your email')).toBeVisible();
  });

  test('existing user re-signup sends magic link (not error)', async ({ page }) => {
    // Use an email that already exists in the database (from fixtures)
    const existingEmail = 'free@example.com';

    await page.click('button[data-plan="free"]');

    await page.fill('input[type="email"]', existingEmail);
    await page.click('input[type="submit"]');

    // Should show same confirmation (magic link sent), not an error
    // This ensures we don't leak information about existing accounts
    await expect(page.locator('text=Check your email')).toBeVisible();

    // Should NOT show any error message about existing account
    await expect(page.locator('text=already exists')).not.toBeVisible();
    await expect(page.locator('text=already registered')).not.toBeVisible();
  });
});
