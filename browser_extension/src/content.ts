/**
 * Content script for TTS browser extension
 *
 * This script is injected into all web pages and serves two primary functions:
 *
 * ## 1. Token Capture from Connect Page
 * When the user visits the TTS extension connect page (/extension/connect),
 * this script captures the API token provided by the server. The token is
 * delivered through two mechanisms for reliability:
 *
 * - **Custom Event**: The connect page dispatches a 'tts-extension-token'
 *   CustomEvent with the token in event.detail.token. This handles the case
 *   where the content script loads before the token is ready.
 *
 * - **Data Attribute**: The connect page also sets data-tts-token on the body
 *   element. This handles the case where the token was already rendered before
 *   the content script loaded (e.g., on page refresh).
 *
 * Security: Token capture is restricted to trusted domains (verynormal.dev,
 * localhost) to prevent malicious sites from injecting tokens.
 *
 * ## 2. Article Extraction on Demand
 * When the user clicks the extension icon, the background script sends an
 * EXTRACT_ARTICLE message to this content script. The content script then:
 *
 * 1. Pre-checks if the page appears to be an article using heuristics
 * 2. Uses Mozilla Readability to extract the main article content
 * 3. Returns the extracted article (title, content, author, etc.) or an error
 *
 * This architecture allows extraction to run in the page context where it has
 * access to the full DOM, while the background script handles API communication.
 */

import { isArticleLike, extract } from './extractor';
import { storeToken } from './auth';
import { isTrustedDomain } from './trustedDomains';
import type { ExtractRequest, ExtractResponse } from './messages';

// Re-export for tests
export { TRUSTED_DOMAINS, isTrustedDomain } from './trustedDomains';

/**
 * Check if we're on the extension connect page and handle token capture
 */
function checkForExtensionToken(): void {
  // Only run on TTS connect pages
  const url = window.location.href;
  if (!url.includes('/extension/connect')) {
    return;
  }

  // Security: Validate domain before accepting tokens
  const hostname = window.location.hostname;
  if (!isTrustedDomain(hostname)) {
    console.warn(
      `TTS Extension: Refusing to accept token from untrusted domain: ${hostname}`
    );
    return;
  }

  // Listen for the custom event from the connect page
  window.addEventListener('tts-extension-token', async (event: Event) => {
    const customEvent = event as CustomEvent<{ token: string }>;
    const token = customEvent.detail?.token;
    if (token) {
      await handleTokenReceived(token);
    }
  });

  // Also check for data attribute (in case event already fired)
  const existingToken = document.body.getAttribute('data-tts-token');
  if (existingToken) {
    handleTokenReceived(existingToken);
  }
}

/**
 * Store the received token and notify background script
 */
async function handleTokenReceived(token: string): Promise<void> {
  try {
    await storeToken(token);
    // Notify background script that connection changed
    chrome.runtime.sendMessage({ type: 'CONNECTION_CHANGED' });
    console.log('TTS Extension: Token stored successfully');
  } catch (error) {
    console.error('TTS Extension: Failed to store token', error);
  }
}

// Run token check when content script loads
checkForExtensionToken();

/**
 * Handle messages from background script
 */
chrome.runtime.onMessage.addListener(
  (
    message: ExtractRequest,
    _sender: chrome.runtime.MessageSender,
    sendResponse: (response: ExtractResponse) => void
  ) => {
    if (message.type === 'EXTRACT_ARTICLE') {
      handleExtractArticle(sendResponse);
      // Return true to indicate we will respond asynchronously
      return true;
    }
    return false;
  }
);

/**
 * Handle article extraction request
 */
function handleExtractArticle(
  sendResponse: (response: ExtractResponse) => void
): void {
  // Pre-check if page looks like an article
  if (!isArticleLike(document)) {
    sendResponse({
      success: false,
      error: 'This page does not appear to be an article',
      errorType: 'NOT_ARTICLE',
    });
    return;
  }

  // Extract article content
  const result = extract(document, window.location.href);

  if (result.success) {
    sendResponse({
      success: true,
      article: result.article,
    });
  } else {
    sendResponse({
      success: false,
      error: result.error,
      errorType: 'EXTRACTION_FAILED',
    });
  }
}
