// e2e/tests/helpers/auth.ts
import { Page, expect } from '@playwright/test';

/**
 * Signs up a new user via the signup modal.
 * Returns the magic link token from the email (requires mailcatcher or similar).
 */
export async function signupWithEmail(page: Page, email: string, plan: 'free' | 'premium_monthly' | 'premium_annual' = 'free') {
  // Click the appropriate signup button based on plan
  if (plan === 'free') {
    await page.click('button[data-plan="free"]');
  } else {
    // For premium plans, first select the plan via toggle if needed
    if (plan === 'premium_monthly') {
      await page.click('input[value="monthly"]');
    }
    await page.click('button[data-plan="' + plan + '"], button[data-pricing-toggle-target="premiumLink"]');
  }

  // Fill in email in the modal
  await page.waitForSelector('dialog[open]');
  await page.fill('input[type="email"]', email);
  await page.click('button[type="submit"]');

  // Wait for confirmation
  await expect(page.locator('text=Check your email')).toBeVisible();
}

/**
 * Authenticates via magic link token.
 * In test mode, we'll extract the token from the Rails test helper.
 */
export async function authenticateWithToken(page: Page, token: string, plan?: string) {
  const url = plan
    ? `/session?token=${token}&plan=${plan}`
    : `/session?token=${token}`;
  await page.goto(url);
}

/**
 * Signs in an existing user by navigating directly with a test token.
 * Requires a test endpoint or fixture setup.
 */
export async function signInAsTestUser(page: Page, email: string) {
  // This will need a test-only endpoint that creates a session
  // For now, use the magic link flow
  await page.goto('/');
  await page.click('button[data-plan="free"]');
  await page.fill('input[type="email"]', email);
  await page.click('button[type="submit"]');
}
