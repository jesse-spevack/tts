/**
 * API client for TTS browser extension
 * Communicates with the TTS Rails backend
 */

const API_BASE_URL = 'https://www.verynormal.fyi';

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
 * Create a new episode from extracted article content
 */
export async function createEpisode(
  token: string,
  request: CreateEpisodeRequest
): Promise<ApiResult<CreateEpisodeResponse>> {
  try {
    const response = await fetch(`${API_BASE_URL}/api/v1/episodes`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`,
      },
      body: JSON.stringify(request),
    });

    if (response.ok) {
      const data = await response.json() as CreateEpisodeResponse;
      return { success: true, data };
    }

    const errorData = await response.json() as ApiError;
    const result: ApiResult<CreateEpisodeResponse> = {
      success: false,
      status: response.status,
      error: errorData.error || getDefaultErrorMessage(response.status),
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
    return {
      success: false,
      status: 0,
      error: error instanceof Error ? error.message : 'Network error',
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
  try {
    const response = await fetch(`${API_BASE_URL}/api/v1/extension_logs`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`,
      },
      body: JSON.stringify(request),
    });

    if (response.ok) {
      const data = await response.json() as LogExtensionFailureResponse;
      return { success: true, data };
    }

    const errorData = await response.json() as ApiError;
    return {
      success: false,
      status: response.status,
      error: errorData.error || getDefaultErrorMessage(response.status),
    };
  } catch (error) {
    return {
      success: false,
      status: 0,
      error: error instanceof Error ? error.message : 'Network error',
    };
  }
}
