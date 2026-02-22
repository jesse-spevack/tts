// e2e/tests/helpers/episodes.ts
import { Page, expect } from '@playwright/test';

/**
 * Submit an episode via URL.
 * Assumes the user is already authenticated and on /episodes.
 */
export async function submitUrlEpisode(page: Page, url: string = 'https://example.com/test-article') {
  await page.goto('/episodes/new');
  // Click URL tab if not already selected
  await page.click('button[data-tab="url"]');
  const urlPanel = page.locator('[data-tab-switch-target="panel"][data-tab="url"]');
  await urlPanel.locator('input[name="url"]').fill(url);
  await urlPanel.locator('input[value="Create Episode"]').click();
  // Should redirect to episodes index
  await page.waitForURL('/episodes');
}

/**
 * Submit an episode via paste text.
 */
export async function submitPasteEpisode(page: Page, text: string) {
  await page.goto('/episodes/new');
  await page.click('button[data-tab="paste"]');
  const pastePanel = page.locator('[data-tab-switch-target="panel"][data-tab="paste"]');
  await pastePanel.locator('textarea[name="text"]').fill(text);
  await pastePanel.locator('input[value="Create Episode"]').click();
  await page.waitForURL('/episodes');
}

/**
 * Wait for an episode card to show a specific status text.
 * Relies on Turbo Stream push via ActionCable — no page reload.
 */
export async function waitForEpisodeStatus(page: Page, statusText: string, options?: { timeout?: number }) {
  const timeout = options?.timeout ?? 90_000;
  await expect(page.locator('[data-testid="episode-card"]').first().locator(`text=${statusText}`))
    .toBeVisible({ timeout });
}

/**
 * Wait for an episode to reach complete status (green dot).
 * Relies on Turbo Stream push via ActionCable — no page reload.
 */
export async function waitForEpisodeComplete(page: Page, options?: { timeout?: number }) {
  const timeout = options?.timeout ?? 120_000;
  await expect(page.locator('[data-testid="episode-card"] .bg-green-500').first())
    .toBeVisible({ timeout });
}

/**
 * Take a named screenshot for the test report.
 */
export async function screenshotTransition(page: Page, name: string) {
  await page.screenshot({ path: `test-results/transitions/${name}.png`, fullPage: true });
}

/**
 * Get the ETA countdown display text.
 */
export async function getEtaText(page: Page): Promise<string> {
  const display = page.locator('[data-eta-countdown-target="display"]').first();
  await expect(display).toBeVisible({ timeout: 30_000 });
  return display.textContent() ?? '';
}

/**
 * Count the number of episode cards on the page.
 */
export async function episodeCardCount(page: Page): Promise<number> {
  return page.locator('[data-testid="episode-card"]').count();
}
