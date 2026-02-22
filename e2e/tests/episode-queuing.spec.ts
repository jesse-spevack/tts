import { test, expect } from '@playwright/test';
import { signInAsNewUser } from './helpers/auth';
import { submitUrlEpisode, screenshotTransition } from './helpers/episodes';

test.describe('Episode Queuing (Simulation Mode)', () => {
  test.describe.configure({ timeout: 360_000 });

  test('3 concurrent URL episodes process and complete via Turbo Stream', async ({ page }) => {
    // 1. Sign in as an unlimited user (free users are limited to 2 episodes/month)
    await signInAsNewUser(page, 'e2e-queuing', { accountType: 'unlimited' });

    // 2. Submit 3 URL episodes in quick succession
    await submitUrlEpisode(page, 'https://example.com/article-1');
    await submitUrlEpisode(page, 'https://example.com/article-2');
    await submitUrlEpisode(page, 'https://example.com/article-3');

    // 3. Verify all 3 episode cards are on the page
    await expect(page.locator('[data-testid="episode-card"]')).toHaveCount(3);

    // 4. Screenshot initial state
    await screenshotTransition(page, 'queuing-3-episodes-submitted');

    // 5. Verify at least one card shows processing indicators
    //    Note: With async adapter, all jobs start immediately (no "Queued..." phase).
    //    With Solid Queue in production, 1 processes while 2 queue.
    const extracting = page.locator('[data-testid="episode-card"]:has-text("Extracting content...")');
    const generating = page.locator('[data-testid="episode-card"]:has-text("Generating audio")');
    await expect.poll(
      async () => (await extracting.count()) + (await generating.count()),
      { timeout: 30_000, message: 'Expected at least one episode to be processing' }
    ).toBeGreaterThanOrEqual(1);

    // 6. Wait for the first episode to complete (green dot via Turbo Stream push)
    await expect(page.locator('[data-testid="episode-card"] .bg-green-500').first())
      .toBeVisible({ timeout: 180_000 });

    // 7. Screenshot after first completion
    await screenshotTransition(page, 'queuing-first-episode-complete');

    // 8. Wait for all 3 episodes to complete
    await expect(page.locator('[data-testid="episode-card"] .bg-green-500'))
      .toHaveCount(3, { timeout: 300_000 });

    // 9. Screenshot final state
    await screenshotTransition(page, 'queuing-all-episodes-complete');
  });
});
