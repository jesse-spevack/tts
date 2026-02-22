import { test, expect } from '@playwright/test';
import { signInAsNewUser } from './helpers/auth';
import {
  submitUrlEpisode,
  submitPasteEpisode,
  waitForEpisodeStatus,
  waitForEpisodeComplete,
  screenshotTransition,
  getEtaText,
} from './helpers/episodes';

test.describe('Episode Lifecycle (Simulation Mode)', () => {
  test.describe.configure({ timeout: 180_000 });

  test('URL episode: pending → preparing → processing (with ETA) → complete', async ({ page }) => {
    // 1. Sign in as a fresh user
    await signInAsNewUser(page, 'e2e-url-lifecycle');

    // 2. Submit a URL episode
    await submitUrlEpisode(page, 'https://example.com/test-article');

    // 3. Screenshot the initial state (pending)
    await screenshotTransition(page, 'url-01-pending');

    // 4. Wait for preparing phase — "Extracting content..."
    await waitForEpisodeStatus(page, 'Extracting content...', { timeout: 90_000 });
    await screenshotTransition(page, 'url-02-preparing');

    // 5. Wait for processing phase — "Generating audio"
    await waitForEpisodeStatus(page, 'Generating audio', { timeout: 90_000 });
    await screenshotTransition(page, 'url-03-processing');

    // 6. Assert ETA countdown is visible and contains "remaining"
    const etaDisplay = page.locator('[data-eta-countdown-target="display"]');
    await expect(etaDisplay).toBeVisible({ timeout: 30_000 });
    const etaText1 = await getEtaText(page);
    expect(etaText1).toContain('remaining');

    // 7. Wait a few seconds and verify ETA is still showing (countdown is decrementing)
    await page.waitForTimeout(3_000);
    const etaText2 = await getEtaText(page);
    expect(etaText2).toContain('remaining');

    // 8. Wait for episode complete (green dot)
    await waitForEpisodeComplete(page, { timeout: 120_000 });
    await screenshotTransition(page, 'url-04-complete');

    // 9. Verify the card is now a link (complete episodes render as <a> tags)
    const card = page.locator('[data-testid="episode-card"]').first();
    const link = card.locator('a');
    await expect(link).toBeVisible();
  });

  test('Paste episode: pending → processing → complete (no preparing phase)', async ({ page }) => {
    // 1. Sign in as a fresh user
    await signInAsNewUser(page, 'e2e-paste-lifecycle');

    // 2. Generate ~500 characters of paste text
    const sentence = 'This is a test article for Playwright E2E testing. ';
    const pasteText = sentence.repeat(10); // ~500 chars

    // 3. Submit via paste
    await submitPasteEpisode(page, pasteText);

    // 4. Screenshot initial state
    await screenshotTransition(page, 'paste-01-pending');

    // 5. Verify "Extracting content..." does NOT appear — paste skips preparing
    const card = page.locator('[data-testid="episode-card"]').first();
    await expect(card.locator('text=Extracting content...')).not.toBeVisible({ timeout: 5_000 });

    // 6. Wait for processing phase — "Generating audio"
    await waitForEpisodeStatus(page, 'Generating audio', { timeout: 90_000 });
    await screenshotTransition(page, 'paste-02-processing');

    // 7. Wait for complete (green dot)
    await waitForEpisodeComplete(page, { timeout: 120_000 });
    await screenshotTransition(page, 'paste-03-complete');
  });
});
