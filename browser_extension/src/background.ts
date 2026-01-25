/**
 * Background service worker for TTS browser extension
 * Handles icon clicks and coordinates the extraction/send flow
 *
 * This file serves as the main entry point for the background script,
 * delegating to specialized modules for specific functionality:
 * - messages.ts: Message type definitions
 * - errorHandling.ts: Error classification and handling
 * - contextMenu.ts: Right-click menu management
 * - api.ts: Backend API communication
 * - icons.ts: Badge/icon state management
 * - auth.ts: Token storage and validation
 * - debounce.ts: Double-click prevention
 */

import { getToken, isConnected } from './auth';
import { BASE_URL } from './config';
import { setIconState } from './icons';
import { createEpisode } from './api';
import { shouldDebounce, recordSuccessfulSend } from './debounce';
import { setupContextMenu, registerContextMenuListeners } from './contextMenu';
import {
  handleApiError,
  handleExtractionError,
  handleExtensionError,
} from './errorHandling';
import type { ExtractRequest, ExtractResponse } from './messages';

// Re-export message types for consumers (e.g., content.ts)
export type { ExtractRequest, ExtractResponse, ExtractedArticle } from './messages';

/**
 * Handle extension icon click
 * Main entry point for user interaction
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
      chrome.tabs.create({ url: `${BASE_URL}/extension/connect` });
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
    await handleExtensionError(error, tab.url);
  }
});

/**
 * Handle extension installation
 * Sets up context menus and logs installation
 */
chrome.runtime.onInstalled.addListener(() => {
  console.log('TTS Extension installed');
  setupContextMenu();
});

// Register context menu click handler
registerContextMenuListeners();
