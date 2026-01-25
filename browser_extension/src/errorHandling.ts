/**
 * Error handling utilities for TTS browser extension
 * Centralizes error classification, handling, and logging
 */

import { getToken, clearToken } from './auth';
import { setIconState } from './icons';
import { logExtensionFailure } from './api';

/**
 * Network error message patterns that indicate connectivity issues
 */
const NETWORK_ERROR_PATTERNS = [
  'Failed to fetch',
  'NetworkError',
  'Network request failed',
  'net::ERR_',
  'TypeError: Failed to fetch',
];

/**
 * Check if an error is likely a network connectivity issue
 */
export function isNetworkError(error: Error): boolean {
  return NETWORK_ERROR_PATTERNS.some(
    (pattern) => error.message.includes(pattern) || error.name.includes(pattern)
  );
}

/**
 * Handle API errors based on status code
 * Sets appropriate icon state and logs errors when relevant
 */
export async function handleApiError(
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
 * Handle extraction errors from content script
 * Sets error icon state and logs to backend
 */
export async function handleExtractionError(
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
 * Handle general extension errors
 * Determines appropriate icon state and attempts to log the error
 */
export async function handleExtensionError(
  error: unknown,
  url: string
): Promise<void> {
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
    if (token && url) {
      await logExtensionFailure(token, {
        url,
        error_type: 'EXTENSION_ERROR',
        error_message: error instanceof Error ? error.message : 'Unknown error',
      });
    }
  } catch {
    // Ignore logging failures
  }
}
