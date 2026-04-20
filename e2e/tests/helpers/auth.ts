// e2e/tests/helpers/auth.ts
import { Page, APIRequestContext, expect } from '@playwright/test';

/**
 * Test user emails matching fixtures in test/fixtures/users.yml
 */
export const TEST_USERS = {
  free: 'free@example.com',
  subscriber: 'subscriber@example.com',
  canceled: 'canceled@example.com',
  pastDue: 'pastdue@example.com',
  complimentary: 'complimentary@example.com',
  unlimited: 'unlimited@example.com',
  canceling: 'canceling@example.com',
};

/**
 * Signs in as a test user by:
 * 1. Fetching a fresh magic link token from the test endpoint
 * 2. Visiting the session URL with that token
 *
 * Only works in development/test environments.
 */
export async function signInAs(page: Page, email: string, redirectTo: string = '/episodes') {
  // Fetch a fresh token from the test endpoint (uses baseURL from playwright config)
  const response = await page.request.get(`/test/magic_link_token/${encodeURIComponent(email)}`);

  if (!response.ok()) {
    const body = await response.text();
    throw new Error(`Failed to get magic link token for ${email}: ${response.status()} - ${body.substring(0, 200)}`);
  }

  const contentType = response.headers()['content-type'] || '';
  if (!contentType.includes('application/json')) {
    const body = await response.text();
    throw new Error(`Expected JSON but got ${contentType}. Body: ${body.substring(0, 200)}`);
  }

  const { token } = await response.json();

  // Authenticate via the magic link (uses /auth route)
  await page.goto(`/auth?token=${token}`);

  // Should be redirected to episodes (or wherever authenticated users go)
  await page.goto(redirectTo);
}

/**
 * Signs in as a free user
 */
export async function signInAsFreeUser(page: Page) {
  await signInAs(page, TEST_USERS.free);
}

/**
 * Signs in as a premium subscriber
 */
export async function signInAsPremiumUser(page: Page) {
  await signInAs(page, TEST_USERS.subscriber);
}

/**
 * Signs in as a canceled subscriber
 */
export async function signInAsCanceledUser(page: Page) {
  await signInAs(page, TEST_USERS.canceled);
}

/**
 * Signs in as a past due subscriber
 */
export async function signInAsPastDueUser(page: Page) {
  await signInAs(page, TEST_USERS.pastDue);
}

/**
 * Signs in as a subscriber with pending cancellation
 */
export async function signInAsCancelingUser(page: Page) {
  await signInAs(page, TEST_USERS.canceling);
}

/**
 * Signs up a new user via the signup modal.
 * Clicks the free or credit_pack CTA, fills the email, and waits for confirmation.
 * For credit_pack signups, optionally pass packSize (5 | 10 | 20) to target a specific pack CTA.
 */
export async function signupWithEmail(
  page: Page,
  email: string,
  options: { plan?: 'free' | 'credit_pack'; packSize?: 5 | 10 | 20 } = {}
) {
  const plan = options.plan ?? 'free';

  if (plan === 'credit_pack' && options.packSize) {
    await page.click(`button[data-plan="credit_pack"][data-pack-size="${options.packSize}"]`);
  } else if (plan === 'credit_pack') {
    await page.locator('button[data-plan="credit_pack"]').first().click();
  } else {
    await page.locator('button[data-plan="free"]').first().click();
  }

  // Fill in email in the modal
  await page.waitForSelector('dialog[open]');
  await page.fill('input[type="email"]', email);
  await page.click('input[type="submit"]');

  // Wait for confirmation
  await expect(page.locator('text=Check your email')).toBeVisible();
}

/**
 * Authenticates via magic link token.
 */
export async function authenticateWithToken(page: Page, token: string) {
  await page.goto(`/auth?token=${token}`);
}

/**
 * Creates a fresh test user and returns the auth token.
 * Email must end with @test.example.com for cleanup via rake task.
 * Optional accountType: 'standard' (default), 'complimentary', or 'unlimited'.
 */
export async function createTestUser(
  request: APIRequestContext,
  email?: string,
  options?: { accountType?: string }
): Promise<{ token: string; email: string }> {
  const testEmail = email || `test-${Date.now()}@test.example.com`;

  const data: Record<string, string> = { email: testEmail };
  if (options?.accountType) {
    data.account_type = options.accountType;
  }

  const response = await request.post('/test/create_user', { data });

  if (!response.ok()) {
    const body = await response.text();
    throw new Error(`Failed to create test user: ${response.status()} - ${body}`);
  }

  return response.json();
}

/**
 * Creates a fresh test user and signs in.
 * Returns the email for reference.
 * Optional accountType: 'standard' (default), 'complimentary', or 'unlimited'.
 */
export async function signInAsNewUser(
  page: Page,
  emailPrefix: string = 'test',
  options?: { accountType?: string }
): Promise<string> {
  const email = `${emailPrefix}-${Date.now()}@test.example.com`;
  const { token } = await createTestUser(page.request, email, options);
  await page.goto(`/auth?token=${token}`);
  return email;
}
