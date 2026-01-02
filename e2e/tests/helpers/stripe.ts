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
 * Stripe Checkout is a hosted page with its own UI.
 */
export async function fillStripeCheckout(page: Page, cardNumber: string = STRIPE_TEST_CARDS.success) {
  // Wait for Stripe checkout page to load
  await page.waitForURL(/checkout\.stripe\.com/, { timeout: 10000 });

  // Wait for the subscribe button to be visible (indicates page loaded)
  await page.waitForSelector('button:has-text("Subscribe"), button:has-text("Pay")', { timeout: 10000 });

  // Select Card payment method - click on the Card row/label
  // Use the visible Card label text which is more reliable
  await page.locator('#payment-method-label-card, label:has-text("Card")').first().click({ force: true });

  // Wait for card form to appear
  await page.waitForTimeout(1000);

  // Fill card number - look for input with card number placeholder
  const cardInput = page.locator('input[placeholder*="1234" i], input[autocomplete="cc-number"]').first();
  await cardInput.waitFor({ state: 'visible', timeout: 10000 });
  await cardInput.fill(cardNumber);

  // Fill expiry
  const expiryInput = page.locator('input[placeholder*="MM" i], input[autocomplete="cc-exp"]').first();
  await expiryInput.fill('12/30');

  // Fill CVC
  const cvcInput = page.locator('input[placeholder*="CVC" i], input[autocomplete="cc-csc"]').first();
  await cvcInput.fill('123');

  // Fill cardholder name if visible
  const nameInput = page.locator('input[placeholder*="name" i], input[autocomplete="cc-name"]').first();
  if (await nameInput.isVisible({ timeout: 1000 }).catch(() => false)) {
    await nameInput.fill('Test User');
  }

  // Fill ZIP if visible
  const zipInput = page.locator('input[placeholder*="ZIP" i], input[autocomplete="postal-code"]').first();
  if (await zipInput.isVisible({ timeout: 1000 }).catch(() => false)) {
    await zipInput.fill('12345');
  }

  // Uncheck "Save my information for faster checkout" to skip Stripe Link phone validation
  const saveInfoCheckbox = page.locator('input[type="checkbox"]').first();
  if (await saveInfoCheckbox.isChecked().catch(() => false)) {
    await saveInfoCheckbox.uncheck();
  }

  // Wait a moment for validation
  await page.waitForTimeout(500);

  // Submit payment
  const submitButton = page.locator('button:has-text("Subscribe"), button:has-text("Pay")').first();
  await submitButton.scrollIntoViewIfNeeded();
  await submitButton.click();

  // Wait for processing to complete (redirect back to our site)
  await page.waitForURL(/localhost|checkout\/success/, { timeout: 60000 });
}

/**
 * Waits for redirect back from Stripe to success page and verifies it loaded.
 */
export async function waitForCheckoutSuccess(page: Page) {
  await page.waitForURL(/\/checkout\/success/, { timeout: 30000 });
  await expect(page.locator('h1:has-text("Welcome to Premium")')).toBeVisible();
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
