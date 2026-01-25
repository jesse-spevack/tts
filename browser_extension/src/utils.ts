/**
 * Utility functions for the TTS browser extension
 */

/**
 * Extract the main content URL from the current page
 */
export function getCurrentUrl(): string {
  return window.location.href;
}

/**
 * Extract the page title
 */
export function getPageTitle(): string {
  return document.title;
}

/**
 * Check if a URL is valid for article extraction
 */
export function isValidArticleUrl(url: string): boolean {
  try {
    const parsed = new URL(url);
    return parsed.protocol === 'http:' || parsed.protocol === 'https:';
  } catch {
    return false;
  }
}

/**
 * Send a message to the background script
 */
export async function sendToBackground<T>(
  action: string,
  payload: Record<string, unknown>
): Promise<T> {
  return new Promise((resolve, reject) => {
    chrome.runtime.sendMessage({ action, ...payload }, (response) => {
      if (chrome.runtime.lastError) {
        reject(new Error(chrome.runtime.lastError.message));
      } else {
        resolve(response as T);
      }
    });
  });
}
