/**
 * Debounce module to prevent accidental double-sends
 * Tracks last successful send per URL and skips API calls within window
 */

const DEBOUNCE_WINDOW_MS = 5000;

interface LastSend {
  url: string;
  timestamp: number;
}

// In-memory tracking for current session
// Using chrome.storage.local would persist across service worker restarts
// but 5 seconds is short enough that in-memory is fine
let lastSuccessfulSend: LastSend | null = null;

/**
 * Check if a URL was recently sent successfully (within debounce window)
 * @returns true if the URL should be debounced (skip the send)
 */
export function shouldDebounce(url: string): boolean {
  if (!lastSuccessfulSend) {
    return false;
  }

  const now = Date.now();
  const elapsed = now - lastSuccessfulSend.timestamp;

  // Same URL within debounce window
  if (lastSuccessfulSend.url === url && elapsed < DEBOUNCE_WINDOW_MS) {
    return true;
  }

  return false;
}

/**
 * Record a successful send for debouncing
 */
export function recordSuccessfulSend(url: string): void {
  lastSuccessfulSend = {
    url,
    timestamp: Date.now(),
  };
}

/**
 * Clear the debounce state (for testing)
 */
export function clearDebounceState(): void {
  lastSuccessfulSend = null;
}

/**
 * Get debounce window in milliseconds (for testing)
 */
export function getDebounceWindowMs(): number {
  return DEBOUNCE_WINDOW_MS;
}
