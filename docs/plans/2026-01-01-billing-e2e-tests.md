# Billing E2E Tests Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create comprehensive Playwright E2E tests for all billing and signup flows.

**Architecture:** Playwright tests in `e2e/` directory, testing against local Rails server. Tests will use Stripe test mode with test card numbers. Magic link flow will be intercepted via test hooks.

**Tech Stack:** Playwright, TypeScript, Stripe test mode

---

## Task 1: Set Up Playwright Project

**Files:**
- Create: `e2e/playwright.config.ts`
- Create: `e2e/package.json`
- Create: `e2e/tsconfig.json`

**Step 1: Create package.json**

```json
{
  "name": "tts-e2e-tests",
  "version": "1.0.0",
  "scripts": {
    "test": "playwright test",
    "test:headed": "playwright test --headed",
    "test:ui": "playwright test --ui"
  },
  "devDependencies": {
    "@playwright/test": "^1.40.0",
    "typescript": "^5.3.0"
  }
}
```

**Step 2: Create tsconfig.json**

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "outDir": "dist"
  },
  "include": ["**/*.ts"]
}
```

**Step 3: Create playwright.config.ts**

```typescript
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './tests',
  fullyParallel: false, // Run sequentially for Stripe state
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: 1,
  reporter: 'html',
  use: {
    baseURL: 'http://localhost:3000',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
  webServer: {
    command: 'cd .. && bin/rails server -p 3000',
    url: 'http://localhost:3000',
    reuseExistingServer: !process.env.CI,
    timeout: 120 * 1000,
  },
});
```

**Step 4: Install dependencies**

Run: `cd e2e && npm install`
Expected: Dependencies installed, `node_modules/` created

**Step 5: Install Playwright browsers**

Run: `cd e2e && npx playwright install chromium`
Expected: Chromium browser downloaded

**Step 6: Commit**

```bash
git add e2e/
git commit -m "chore: Set up Playwright E2E test infrastructure"
```

---

## Task 2: Create Test Helpers

**Files:**
- Create: `e2e/tests/helpers/auth.ts`
- Create: `e2e/tests/helpers/stripe.ts`

**Step 1: Create auth helper**

```typescript
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
```

**Step 2: Create Stripe helper**

```typescript
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
```

**Step 3: Commit**

```bash
git add e2e/tests/helpers/
git commit -m "feat: Add auth and Stripe test helpers"
```

---

## Task 3: Landing Page Signup Tests

**Files:**
- Create: `e2e/tests/signup-flows.spec.ts`

**Step 1: Create signup flow tests**

```typescript
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
    await expect(modal.locator('h2')).toContainText('Start listening free');
    await expect(modal.locator('text=2 episodes/month')).toBeVisible();
  });

  test('premium annual signup opens modal with correct heading', async ({ page }) => {
    // Scroll to pricing section
    await page.goto('/#pricing');

    // Verify annual is selected by default
    await expect(page.locator('input[value="annual"]')).toBeChecked();

    // Click "Get Premium" button
    await page.click('button[data-pricing-toggle-target="premiumLink"]');

    // Verify modal opens with premium content
    const modal = page.locator('dialog[open]');
    await expect(modal).toBeVisible();
    await expect(modal.locator('h2')).toContainText('Get Premium');
  });

  test('premium monthly signup opens modal after toggle', async ({ page }) => {
    // Scroll to pricing section
    await page.goto('/#pricing');

    // Toggle to monthly
    await page.click('input[value="monthly"]');

    // Click "Get Premium" button
    await page.click('button[data-pricing-toggle-target="premiumLink"]');

    // Verify modal opens
    const modal = page.locator('dialog[open]');
    await expect(modal).toBeVisible();

    // Verify the button has monthly plan data
    const premiumButton = page.locator('button[data-pricing-toggle-target="premiumLink"]');
    await expect(premiumButton).toHaveAttribute('data-plan', 'premium_monthly');
  });

  test('modal can be closed with X button', async ({ page }) => {
    await page.click('button[data-plan="free"]');

    const modal = page.locator('dialog[open]');
    await expect(modal).toBeVisible();

    // Close modal
    await page.click('button[data-action="click->signup-modal#close"]');
    await expect(modal).not.toBeVisible();
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

    await page.fill('input[type="email"]', 'not-an-email');
    await page.click('button[type="submit"]');

    // Browser validation should prevent submission
    const emailInput = page.locator('input[type="email"]');
    await expect(emailInput).toBeFocused();
  });

  test('signup form submits and shows confirmation', async ({ page }) => {
    await page.click('button[data-plan="free"]');

    await page.fill('input[type="email"]', 'test-e2e@example.com');
    await page.click('button[type="submit"]');

    // Should show confirmation message
    await expect(page.locator('text=Check your email')).toBeVisible();
  });
});
```

**Step 2: Run tests to verify they work**

Run: `cd e2e && npm test -- --grep "Landing Page Signup"`
Expected: Tests run (some may fail if server not running, that's OK)

**Step 3: Commit**

```bash
git add e2e/tests/signup-flows.spec.ts
git commit -m "test: Add landing page signup flow tests"
```

---

## Task 4: Upgrade Page Tests (Free User)

**Files:**
- Create: `e2e/tests/upgrade-flows.spec.ts`

**Step 1: Create upgrade flow tests**

```typescript
// e2e/tests/upgrade-flows.spec.ts
import { test, expect } from '@playwright/test';

test.describe('Upgrade Flows (Free User)', () => {
  // Note: These tests require a logged-in free user session
  // In real implementation, use a test helper to create session

  test('free user sees Upgrade link in header', async ({ page }) => {
    // This test needs authentication setup
    // For now, test the redirect behavior
    await page.goto('/upgrade');

    // Should redirect to login if not authenticated
    await expect(page).toHaveURL('/');
  });

  test('/billing redirects free user to /upgrade', async ({ page }) => {
    // When logged in as free user, /billing should redirect to /upgrade
    // This requires session setup - placeholder for now
    await page.goto('/billing');
    await expect(page).toHaveURL('/');
  });

  test('upgrade page shows pricing toggle', async ({ page }) => {
    // Requires authenticated session
    // Placeholder structure:
    // await signInAsFreeUser(page);
    // await page.goto('/upgrade');
    // await expect(page.locator('input[value="annual"]')).toBeChecked();
    // await expect(page.locator('input[value="monthly"]')).toBeVisible();
  });

  test('upgrade page toggle switches price display', async ({ page }) => {
    // Requires authenticated session
    // await signInAsFreeUser(page);
    // await page.goto('/upgrade');

    // // Annual price visible by default
    // await expect(page.locator('[data-pricing-toggle-target="annualPrice"]')).toBeVisible();
    // await expect(page.locator('[data-pricing-toggle-target="monthlyPrice"]')).toBeHidden();

    // // Toggle to monthly
    // await page.click('input[value="monthly"]');

    // // Monthly price visible
    // await expect(page.locator('[data-pricing-toggle-target="monthlyPrice"]')).toBeVisible();
    // await expect(page.locator('[data-pricing-toggle-target="annualPrice"]')).toBeHidden();
  });

  test('upgrade page shows free plan usage', async ({ page }) => {
    // Requires authenticated session
    // await signInAsFreeUser(page);
    // await page.goto('/upgrade');
    // await expect(page.locator('text=Free Plan')).toBeVisible();
    // await expect(page.locator('text=episodes used this month')).toBeVisible();
  });

  test('subscribe button redirects to Stripe checkout', async ({ page }) => {
    // Requires authenticated session
    // await signInAsFreeUser(page);
    // await page.goto('/upgrade');
    // await page.click('button:has-text("Subscribe")');
    // await expect(page).toHaveURL(/checkout\.stripe\.com/);
  });
});
```

**Step 2: Commit**

```bash
git add e2e/tests/upgrade-flows.spec.ts
git commit -m "test: Add upgrade page flow tests (scaffolded)"
```

---

## Task 5: Billing Page Tests (Premium User)

**Files:**
- Create: `e2e/tests/billing-flows.spec.ts`

**Step 1: Create billing flow tests**

```typescript
// e2e/tests/billing-flows.spec.ts
import { test, expect } from '@playwright/test';

test.describe('Billing Flows (Premium User)', () => {
  test('/upgrade redirects premium user to /billing', async ({ page }) => {
    // Requires premium user session
    // await signInAsPremiumUser(page);
    // await page.goto('/upgrade');
    // await expect(page).toHaveURL('/billing');
  });

  test('billing page shows Premium Plan card', async ({ page }) => {
    // Requires premium user session
    // await signInAsPremiumUser(page);
    // await page.goto('/billing');
    // await expect(page.locator('text=Premium Plan')).toBeVisible();
    // await expect(page.locator('text=Renews on')).toBeVisible();
  });

  test('Manage Subscription button opens Stripe portal', async ({ page }) => {
    // Requires premium user session
    // await signInAsPremiumUser(page);
    // await page.goto('/billing');
    // await page.click('button:has-text("Manage Subscription")');
    // await expect(page).toHaveURL(/billing\.stripe\.com/);
  });

  test('billing page accessible from Settings', async ({ page }) => {
    // Requires premium user session
    // await signInAsPremiumUser(page);
    // await page.goto('/settings');
    // await expect(page.locator('text=Billing')).toBeVisible();
    // await page.click('a:has-text("Manage Billing")');
    // await expect(page).toHaveURL('/billing');
  });
});

test.describe('Billing Edge Cases', () => {
  test('canceled subscription shows upgrade options', async ({ page }) => {
    // Requires canceled subscription user
    // await signInAsCanceledUser(page);
    // await page.goto('/billing');
    // await expect(page.locator('text=Subscription Ended')).toBeVisible();
    // await expect(page.locator('button:has-text("Subscribe")')).toBeVisible();
  });

  test('past due subscription shows Fix Payment button', async ({ page }) => {
    // Requires past due subscription user
    // await signInAsPastDueUser(page);
    // await page.goto('/billing');
    // await expect(page.locator('text=Payment Failed')).toBeVisible();
    // await expect(page.locator('button:has-text("Fix Payment")')).toBeVisible();
  });
});
```

**Step 2: Commit**

```bash
git add e2e/tests/billing-flows.spec.ts
git commit -m "test: Add billing page flow tests (scaffolded)"
```

---

## Task 6: Authentication Redirect Tests

**Files:**
- Create: `e2e/tests/auth-redirects.spec.ts`

**Step 1: Create redirect tests**

```typescript
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
    await expect(page.locator('text=Choose your plan')).toBeVisible();
  });
});
```

**Step 2: Run these tests (they should pass without auth)**

Run: `cd e2e && npm test -- --grep "Authentication Redirects"`
Expected: All redirect tests pass

**Step 3: Commit**

```bash
git add e2e/tests/auth-redirects.spec.ts
git commit -m "test: Add authentication redirect tests"
```

---

## Task 7: Create Test Session Helper (Rails Side)

**Files:**
- Create: `app/controllers/test_sessions_controller.rb`
- Modify: `config/routes.rb`

**Step 1: Create test sessions controller (only for test/development)**

```ruby
# app/controllers/test_sessions_controller.rb
class TestSessionsController < ApplicationController
  before_action :ensure_test_environment

  def create
    user = User.find_by!(email_address: params[:email])
    start_new_session_for(user)
    redirect_to params[:redirect_to] || episodes_path
  end

  private

  def ensure_test_environment
    unless Rails.env.test? || Rails.env.development?
      raise ActionController::RoutingError, "Not Found"
    end
  end
end
```

**Step 2: Add route (development/test only)**

Add to `config/routes.rb` inside a conditional block:

```ruby
# In config/routes.rb, add near the bottom before the final 'end':
if Rails.env.development? || Rails.env.test?
  post "test_session", to: "test_sessions#create"
end
```

**Step 3: Commit**

```bash
git add app/controllers/test_sessions_controller.rb config/routes.rb
git commit -m "feat: Add test session endpoint for E2E tests"
```

---

## Task 8: Update Test Helpers with Session Support

**Files:**
- Modify: `e2e/tests/helpers/auth.ts`

**Step 1: Update auth helper with working session creation**

```typescript
// e2e/tests/helpers/auth.ts
import { Page, expect } from '@playwright/test';

/**
 * Signs in as a test user by hitting the test session endpoint.
 * Only works in development/test environments.
 */
export async function signInAs(page: Page, email: string, redirectTo: string = '/episodes') {
  await page.request.post('http://localhost:3000/test_session', {
    form: {
      email: email,
      redirect_to: redirectTo,
    },
  });
  await page.goto(redirectTo);
}

/**
 * Test user emails matching fixtures
 */
export const TEST_USERS = {
  free: 'free@example.com',
  subscriber: 'subscriber@example.com',
  canceled: 'canceled@example.com',
  pastDue: 'pastdue@example.com',
  complimentary: 'complimentary@example.com',
  unlimited: 'unlimited@example.com',
};

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
 * Signs out current user
 */
export async function signOut(page: Page) {
  await page.goto('/session', {
    method: 'DELETE'
  });
}
```

**Step 2: Commit**

```bash
git add e2e/tests/helpers/auth.ts
git commit -m "feat: Add session helpers for E2E test authentication"
```

---

## Task 9: Enable Authenticated Tests

**Files:**
- Modify: `e2e/tests/upgrade-flows.spec.ts`
- Modify: `e2e/tests/billing-flows.spec.ts`

**Step 1: Update upgrade flows with real authentication**

```typescript
// e2e/tests/upgrade-flows.spec.ts
import { test, expect } from '@playwright/test';
import { signInAsFreeUser, signInAsPremiumUser } from './helpers/auth';

test.describe('Upgrade Flows (Free User)', () => {
  test('free user sees Upgrade link in header', async ({ page }) => {
    await signInAsFreeUser(page);
    await expect(page.locator('a:has-text("Upgrade")')).toBeVisible();
  });

  test('clicking Upgrade goes to /upgrade page', async ({ page }) => {
    await signInAsFreeUser(page);
    await page.click('a:has-text("Upgrade")');
    await expect(page).toHaveURL('/upgrade');
  });

  test('/billing redirects free user to /upgrade', async ({ page }) => {
    await signInAsFreeUser(page);
    await page.goto('/billing');
    await expect(page).toHaveURL('/upgrade');
  });

  test('upgrade page shows pricing toggle with annual default', async ({ page }) => {
    await signInAsFreeUser(page);
    await page.goto('/upgrade');
    await expect(page.locator('input[value="annual"]')).toBeChecked();
    await expect(page.locator('input[value="monthly"]')).not.toBeChecked();
  });

  test('upgrade page toggle switches price display', async ({ page }) => {
    await signInAsFreeUser(page);
    await page.goto('/upgrade');

    // Annual price visible by default
    await expect(page.locator('[data-pricing-toggle-target="annualPrice"]')).toBeVisible();
    await expect(page.locator('[data-pricing-toggle-target="monthlyPrice"]')).toBeHidden();

    // Toggle to monthly
    await page.click('input[value="monthly"]');

    // Monthly price visible
    await expect(page.locator('[data-pricing-toggle-target="monthlyPrice"]')).toBeVisible();
    await expect(page.locator('[data-pricing-toggle-target="annualPrice"]')).toBeHidden();
  });

  test('upgrade page shows free plan usage', async ({ page }) => {
    await signInAsFreeUser(page);
    await page.goto('/upgrade');
    await expect(page.locator('text=Free Plan')).toBeVisible();
  });

  test('subscribe button redirects to Stripe checkout', async ({ page }) => {
    await signInAsFreeUser(page);
    await page.goto('/upgrade');

    // Click subscribe - will redirect to Stripe
    const [popup] = await Promise.all([
      page.waitForURL(/checkout\.stripe\.com/),
      page.click('input[type="submit"][value="Subscribe"]'),
    ]);

    await expect(page).toHaveURL(/checkout\.stripe\.com/);
  });
});
```

**Step 2: Update billing flows with real authentication**

```typescript
// e2e/tests/billing-flows.spec.ts
import { test, expect } from '@playwright/test';
import { signInAsFreeUser, signInAsPremiumUser, signInAsCanceledUser, signInAsPastDueUser } from './helpers/auth';

test.describe('Billing Flows (Premium User)', () => {
  test('/upgrade redirects premium user to /billing', async ({ page }) => {
    await signInAsPremiumUser(page);
    await page.goto('/upgrade');
    await expect(page).toHaveURL('/billing');
  });

  test('billing page shows Premium Plan card', async ({ page }) => {
    await signInAsPremiumUser(page);
    await page.goto('/billing');
    await expect(page.locator('text=Premium Plan')).toBeVisible();
    await expect(page.locator('text=Renews on')).toBeVisible();
  });

  test('Manage Subscription button opens Stripe portal', async ({ page }) => {
    await signInAsPremiumUser(page);
    await page.goto('/billing');

    await Promise.all([
      page.waitForURL(/billing\.stripe\.com/),
      page.click('button:has-text("Manage Subscription")'),
    ]);

    await expect(page).toHaveURL(/billing\.stripe\.com/);
  });

  test('billing page accessible from Settings', async ({ page }) => {
    await signInAsPremiumUser(page);
    await page.goto('/settings');
    await expect(page.locator('h2:has-text("Billing")')).toBeVisible();
    await page.click('a:has-text("Manage Billing")');
    await expect(page).toHaveURL('/billing');
  });

  test('premium user does not see Upgrade in header', async ({ page }) => {
    await signInAsPremiumUser(page);
    await expect(page.locator('a:has-text("Upgrade")')).not.toBeVisible();
  });
});

test.describe('Billing Edge Cases', () => {
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
```

**Step 3: Commit**

```bash
git add e2e/tests/upgrade-flows.spec.ts e2e/tests/billing-flows.spec.ts
git commit -m "test: Enable authenticated E2E tests for upgrade and billing"
```

---

## Task 10: Add .gitignore for E2E

**Files:**
- Create: `e2e/.gitignore`

**Step 1: Create gitignore**

```
node_modules/
dist/
test-results/
playwright-report/
playwright/.cache/
```

**Step 2: Commit**

```bash
git add e2e/.gitignore
git commit -m "chore: Add E2E gitignore"
```

---

## Task 11: Final Integration Test

**Step 1: Seed test database**

Run: `cd /Users/jesse/code/tts && bin/rails db:fixtures:load RAILS_ENV=development`
Expected: Fixtures loaded into development database

**Step 2: Start Rails server**

Run: `cd /Users/jesse/code/tts && bin/rails server`
Expected: Server running on localhost:3000

**Step 3: Run all E2E tests**

Run: `cd /Users/jesse/code/tts/e2e && npm test`
Expected: All tests pass

**Step 4: Final commit**

```bash
git add -A
git commit -m "test: Complete E2E billing test suite"
```

---

Plan complete and saved to `docs/plans/2026-01-01-billing-e2e-tests.md`.

To execute:
1. Open a new Claude session in the worktree
2. Use executing-plans skill to run the plan in batches
3. After each batch, bring the progress report back here for review
