/**
 * Content script for TTS browser extension
 * Runs in the context of web pages to extract article content
 */

import { isArticleLike, extract } from './extractor';
import type { ExtractRequest, ExtractResponse } from './background';

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
