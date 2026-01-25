/**
 * Content script for TTS browser extension
 * Runs in the context of web pages to extract article content
 */

import { isArticleLike, extract } from './extractor';
import { storeToken } from './auth';
import type { ExtractRequest, ExtractResponse } from './background';

/**
 * Check if we're on the extension connect page and handle token capture
 */
function checkForExtensionToken(): void {
  // Only run on TTS connect pages
  const url = window.location.href;
  if (!url.includes('/extension/connect')) {
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
