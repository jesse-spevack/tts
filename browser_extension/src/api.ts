/**
 * API client for TTS browser extension
 * Communicates with the TTS Rails backend
 */

import { BASE_URL } from './config';

/** Default timeout for API requests in milliseconds */
const API_TIMEOUT_MS = 30000;

export interface CreateEpisodeRequest {
  title: string;
  content: string;
  url: string;
  author?: string;
  description?: string;
}

export interface CreateEpisodeResponse {
  id: string;
}

export interface ApiError {
  error: string;
}

export interface LogExtensionFailureRequest {
  url: string;
  error_type: string;
  error_message: string;
}

export interface LogExtensionFailureResponse {
  logged: boolean;
}

export type ApiResult<T> =
  | { success: true; data: T }
  | { success: false; status: number; error: string; retryAfter?: number };

/**
 * Safely parse JSON response, returning null if parsing fails
 * (e.g., when server returns HTML error pages instead of JSON)
 */
async function safeParseJson<T>(response: Response): Promise<T | null> {
  try {
    return await response.json() as T;
  } catch {
    return null;
  }
}

/**
 * Create a new episode from extracted article content
 */
export async function createEpisode(
  token: string,
  request: CreateEpisodeRequest
): Promise<ApiResult<CreateEpisodeResponse>> {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), API_TIMEOUT_MS);

  try {
    const response = await fetch(`${BASE_URL}/api/v1/episodes`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`,
      },
      body: JSON.stringify(request),
      signal: controller.signal,
    });

    clearTimeout(timeoutId);

    if (response.ok) {
      const data = await safeParseJson<CreateEpisodeResponse>(response);
      if (data) {
        return { success: true, data };
      }
      return {
        success: false,
        status: response.status,
        error: 'Invalid response format',
      };
    }

    const errorData = await safeParseJson<ApiError>(response);
    const result: ApiResult<CreateEpisodeResponse> = {
      success: false,
      status: response.status,
      error: errorData?.error || getDefaultErrorMessage(response.status),
    };

    // Extract Retry-After header for rate-limited responses
    if (response.status === 429) {
      const retryAfter = response.headers.get('Retry-After');
      if (retryAfter) {
        result.retryAfter = parseInt(retryAfter, 10);
      }
    }

    return result;
  } catch (error) {
    clearTimeout(timeoutId);
    const errorMessage = error instanceof Error
      ? (error.name === 'AbortError' ? 'Request timed out' : error.message)
      : 'Network error';
    return {
      success: false,
      status: 0,
      error: errorMessage,
    };
  }
}

/**
 * Get a human-readable error message for common HTTP status codes
 */
function getDefaultErrorMessage(status: number): string {
  switch (status) {
    case 401:
      return 'Unauthorized - please reconnect the extension';
    case 422:
      return 'Invalid article content';
    case 429:
      return 'Episode limit reached';
    default:
      return `Request failed with status ${status}`;
  }
}

/**
 * Log an extension failure for debugging/analytics
 */
export async function logExtensionFailure(
  token: string,
  request: LogExtensionFailureRequest
): Promise<ApiResult<LogExtensionFailureResponse>> {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), API_TIMEOUT_MS);

  try {
    const response = await fetch(`${BASE_URL}/api/v1/extension_logs`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`,
      },
      body: JSON.stringify(request),
      signal: controller.signal,
    });

    clearTimeout(timeoutId);

    if (response.ok) {
      const data = await safeParseJson<LogExtensionFailureResponse>(response);
      if (data) {
        return { success: true, data };
      }
      return {
        success: false,
        status: response.status,
        error: 'Invalid response format',
      };
    }

    const errorData = await safeParseJson<ApiError>(response);
    return {
      success: false,
      status: response.status,
      error: errorData?.error || getDefaultErrorMessage(response.status),
    };
  } catch (error) {
    clearTimeout(timeoutId);
    const errorMessage = error instanceof Error
      ? (error.name === 'AbortError' ? 'Request timed out' : error.message)
      : 'Network error';
    return {
      success: false,
      status: 0,
      error: errorMessage,
    };
  }
}
