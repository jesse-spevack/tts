// e2e/tests/signup-flows.spec.ts
import { test, expect } from '@playwright/test';

test.describe('Landing Page Signup Flows', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
  });

  test('free signup opens modal with correct heading', async ({ page }) => {
    // Click "Start listening free" button (first occurrence — hero CTA)
    await page.locator('button[data-plan="free"]').first().click();

    // Verify modal opens with correct content
    const modal = page.locator('dialog[open]');
    await expect(modal).toBeVisible();
    await expect(modal.locator('h3')).toContainText('Start listening free');
    await expect(modal.locator('text=2 episodes/month')).toBeVisible();
  });

  for (const packSize of [5, 10, 20] as const) {
    test(`credit pack (${packSize}) signup opens modal with pack size populated`, async ({ page }) => {
      // Scroll to pricing section
      await page.goto('/#pricing');

      // Click the pack-specific CTA
      await page
        .locator(`button[data-plan="credit_pack"][data-pack-size="${packSize}"]`)
        .click();

      const modal = page.locator('dialog[open]');
      await expect(modal).toBeVisible();

      // Hidden plan + pack_size fields should carry the selection into the form
      await expect(modal.locator('input[name="plan"]')).toHaveValue('credit_pack');
      await expect(modal.locator('input[name="pack_size"]')).toHaveValue(String(packSize));
    });
  }

  test('modal can be closed by clicking backdrop', async ({ page }) => {
    await page.locator('button[data-plan="free"]').first().click();

    const modal = page.locator('dialog[open]');
    await expect(modal).toBeVisible();

    // Click outside modal (on backdrop)
    await page.click('dialog[open]', { position: { x: 10, y: 10 } });
    await expect(modal).not.toBeVisible();
  });

  test('email validation shows error for invalid email', async ({ page }) => {
    await page.locator('button[data-plan="free"]').first().click();

    // Fill with invalid email
    await page.fill('input[type="email"]', 'not-an-email');

    // Click the submit input
    await page.click('input[type="submit"]');

    // Browser validation should prevent submission
    const emailInput = page.locator('input[type="email"]');
    await expect(emailInput).toBeFocused();
  });

  test('signup form submits and shows confirmation', async ({ page }) => {
    await page.locator('button[data-plan="free"]').first().click();

    await page.fill('input[type="email"]', 'test-e2e@example.com');
    await page.click('input[type="submit"]');

    // Should show confirmation message
    await expect(page.locator('text=Check your email')).toBeVisible();
  });

  test('existing user re-signup sends magic link (not error)', async ({ page }) => {
    // Use an email that already exists in the database (from fixtures)
    const existingEmail = 'free@example.com';

    await page.locator('button[data-plan="free"]').first().click();

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
