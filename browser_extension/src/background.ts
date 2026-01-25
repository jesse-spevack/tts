/**
 * Background service worker for TTS browser extension
 * Handles icon clicks and coordinates the extraction/send flow
 */

import { getToken, isConnected, clearToken } from './auth';
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
      // Not connected - open auth page directly
      chrome.tabs.create({ url: 'https://www.verynormal.fyi/extension/connect' });
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
      await handleApiError(result.status, result.error, tab.url, token);
    }
  } catch (error) {
    console.error('Error processing article:', error);

    // Check if it's a network error (offline)
    if (error instanceof Error && isNetworkError(error)) {
      await setIconState('offline');
    } else {
      await setIconState('error');
    }

    // Try to log the error (only if we might be online)
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
 * Handle API errors based on status code
 */
async function handleApiError(
  status: number,
  error: string,
  url: string,
  token: string
): Promise<void> {
  switch (status) {
    case 401:
      // Unauthorized - token is invalid or revoked
      await clearToken();
      await setIconState('error');
      // Don't log - token is already invalid
      break;

    case 429:
      // Rate limited
      await setIconState('rate_limited');
      // Don't log rate limits
      break;

    case 0:
      // Network error (fetch failed)
      await setIconState('offline');
      break;

    default:
      // All other errors (including 5xx)
      await setIconState('error');
      // Log the error for debugging
      try {
        await logExtensionFailure(token, {
          url,
          error_type: status >= 500 ? 'SERVER_ERROR' : 'API_ERROR',
          error_message: error,
        });
      } catch {
        // Ignore logging failures
      }
  }
}

/**
 * Check if an error is likely a network connectivity issue
 */
function isNetworkError(error: Error): boolean {
  const networkErrorMessages = [
    'Failed to fetch',
    'NetworkError',
    'Network request failed',
    'net::ERR_',
    'TypeError: Failed to fetch',
  ];
  return networkErrorMessages.some(msg =>
    error.message.includes(msg) || error.name.includes(msg)
  );
}

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

// Listen for installation
chrome.runtime.onInstalled.addListener(() => {
  console.log('TTS Extension installed');
});
