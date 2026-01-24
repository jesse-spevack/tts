/**
 * Background service worker for TTS browser extension
 * Handles icon clicks and coordinates the extraction/send flow
 */

import { getToken, isConnected } from './auth';
import { setIconState } from './icons';
import { createEpisode, logExtensionFailure } from './api';
import { shouldDebounce, recordSuccessfulSend } from './debounce';

// Message types for communication with content script
export interface ExtractRequest {
  type: 'EXTRACT_ARTICLE';
}

export interface ExtractedArticle {
  title: string;
  content: string;
  url: string;
  author?: string;
  description?: string;
}

export interface ExtractSuccessResponse {
  success: true;
  article: ExtractedArticle;
}

export interface ExtractErrorResponse {
  success: false;
  error: string;
  errorType: 'NOT_ARTICLE' | 'EXTRACTION_FAILED';
}

export type ExtractResponse = ExtractSuccessResponse | ExtractErrorResponse;

/**
 * Handle extension icon click
 */
chrome.action.onClicked.addListener(async (tab) => {
  if (!tab.id || !tab.url) {
    console.error('No active tab');
    return;
  }

  // Skip chrome:// and other non-http pages
  if (!tab.url.startsWith('http://') && !tab.url.startsWith('https://')) {
    await setIconState('error');
    return;
  }

  try {
    // Check if connected
    const connected = await isConnected();
    if (!connected) {
      // Open popup for connect flow
      // Note: In Manifest V3, we can't programmatically open the popup
      // So we'll open the TTS auth page directly
      chrome.tabs.create({ url: 'https://www.verynormal.fyi/api/v1/extension_token' });
      return;
    }

    // Check for double-click debounce (same URL within 5 seconds)
    if (shouldDebounce(tab.url)) {
      // Silently succeed without making API call
      await setIconState('success');
      return;
    }

    // Show loading state
    await setIconState('loading');

    // Send message to content script to extract article
    const response = await chrome.tabs.sendMessage<ExtractRequest, ExtractResponse>(
      tab.id,
      { type: 'EXTRACT_ARTICLE' }
    );

    if (!response) {
      throw new Error('No response from content script');
    }

    if (!response.success) {
      await handleExtractionError(response.error, response.errorType, tab.url);
      return;
    }

    // Send to API
    const token = await getToken();
    if (!token) {
      await setIconState('error');
      return;
    }

    const result = await createEpisode(token, {
      title: response.article.title,
      content: response.article.content,
      url: response.article.url,
      author: response.article.author,
      description: response.article.description,
    });

    if (result.success) {
      recordSuccessfulSend(tab.url);
      await setIconState('success');
    } else {
      await setIconState('error');

      // Log failure to backend if it's not a rate limit
      if (result.status !== 429) {
        await logExtensionFailure(token, {
          url: tab.url,
          error_type: 'API_ERROR',
          error_message: result.error,
        });
      }
    }
  } catch (error) {
    console.error('Error processing article:', error);
    await setIconState('error');

    // Try to log the error
    try {
      const token = await getToken();
      if (token && tab.url) {
        await logExtensionFailure(token, {
          url: tab.url,
          error_type: 'EXTENSION_ERROR',
          error_message: error instanceof Error ? error.message : 'Unknown error',
        });
      }
    } catch {
      // Ignore logging failures
    }
  }
});

/**
 * Handle extraction errors
 */
async function handleExtractionError(
  error: string,
  errorType: string,
  url: string
): Promise<void> {
  await setIconState('error');

  // Log to backend
  try {
    const token = await getToken();
    if (token) {
      await logExtensionFailure(token, {
        url,
        error_type: errorType,
        error_message: error,
      });
    }
  } catch {
    // Ignore logging failures
  }
}

/**
 * Update popup state based on connection status
 * When connected: disable popup so onClicked fires for direct extraction
 * When disconnected: enable popup for connect flow
 */
async function updatePopupState(): Promise<void> {
  const connected = await isConnected();
  // Empty string disables popup, allowing onClicked to fire
  const popup = connected ? '' : 'popup.html';
  await chrome.action.setPopup({ popup });
}

// Listen for installation to set up initial state
chrome.runtime.onInstalled.addListener(async () => {
  console.log('TTS Extension installed');
  await updatePopupState();
});

// Also check on startup
chrome.runtime.onStartup.addListener(async () => {
  await updatePopupState();
});

// Listen for messages from popup about connection changes
chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message.type === 'CONNECTION_CHANGED') {
    updatePopupState().then(() => sendResponse({ success: true }));
    return true; // Keep channel open for async response
  }
  return false;
});

// Listen for storage changes (token added/removed)
chrome.storage.onChanged.addListener((changes, areaName) => {
  if (areaName === 'sync' && changes.tts_api_token) {
    updatePopupState();
  }
});
