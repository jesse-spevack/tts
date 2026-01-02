// e2e/tests/checkout-flows.spec.ts
import { test, expect } from '@playwright/test';
import { signInAsNewUser } from './helpers/auth';
import { fillStripeCheckout, waitForCheckoutSuccess, STRIPE_TEST_CARDS } from './helpers/stripe';

test.describe('Checkout Flows', () => {
  // Uses fresh test users (checkout-*@test.example.com) for isolation.
  // Clean up with: bin/rake test:purge_e2e_users
  test('complete subscription checkout with test card', async ({ page }) => {
    await signInAsNewUser(page, 'checkout');
    await page.goto('/upgrade');

    // Click subscribe (uses annual by default)
    await page.click('input[type="submit"][value="Subscribe"]');

    // Complete Stripe checkout
    await fillStripeCheckout(page, STRIPE_TEST_CARDS.success);

    // Verify success page
    await waitForCheckoutSuccess(page);
    await expect(page.locator('text=Start creating episodes')).toBeVisible();
  });

  // Skip: Running declined card test would still create a checkout session
  // and the user state makes subsequent tests flaky
  test.skip('declined card shows error on Stripe checkout', async ({ page }) => {
    // This would test error handling on Stripe's side
  });
});
