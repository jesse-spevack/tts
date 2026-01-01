// e2e/tests/helpers/stripe.ts
import { Page, expect } from '@playwright/test';

// Stripe test card numbers
export const STRIPE_TEST_CARDS = {
  success: '4242424242424242',
  declined: '4000000000000002',
  requires3ds: '4000002500003155',
};

/**
 * Fills in Stripe checkout form with test card.
 */
export async function fillStripeCheckout(page: Page, cardNumber: string = STRIPE_TEST_CARDS.success) {
  // Wait for Stripe checkout page to load
  await page.waitForURL(/checkout\.stripe\.com/);

  // Fill in card details
  await page.fill('[data-testid="card-number-input"], input[name="cardNumber"]', cardNumber);
  await page.fill('[data-testid="card-expiry-input"], input[name="cardExpiry"]', '12/30');
  await page.fill('[data-testid="card-cvc-input"], input[name="cardCvc"]', '123');

  // Fill in billing details if required
  const nameField = page.locator('input[name="billingName"]');
  if (await nameField.isVisible()) {
    await nameField.fill('Test User');
  }

  // Submit payment
  await page.click('button[type="submit"]:has-text("Subscribe"), button[type="submit"]:has-text("Pay")');
}

/**
 * Waits for redirect back from Stripe to success page.
 */
export async function waitForCheckoutSuccess(page: Page) {
  await page.waitForURL(/\/checkout\/success/);
  await expect(page.locator('text=Thank you')).toBeVisible();
}

/**
 * Fills in Stripe billing portal for managing subscription.
 */
export async function interactWithBillingPortal(page: Page, action: 'cancel' | 'update_payment') {
  await page.waitForURL(/billing\.stripe\.com/);

  if (action === 'cancel') {
    await page.click('text=Cancel plan');
    await page.click('text=Cancel plan', { strict: false }); // Confirmation
  }
}
