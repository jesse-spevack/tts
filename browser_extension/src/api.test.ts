import { createEpisode, CreateEpisodeRequest, logExtensionFailure, LogExtensionFailureRequest } from './api';
import { BASE_URL } from './config';

// Mock fetch globally
const mockFetch = jest.fn();
(globalThis as typeof globalThis & { fetch: typeof fetch }).fetch = mockFetch;

describe('api', () => {
  beforeEach(() => {
    mockFetch.mockReset();
  });

  describe('createEpisode', () => {
    const validRequest: CreateEpisodeRequest = {
      title: 'Test Article',
      content: 'Article content here',
      url: 'https://example.com/article',
      author: 'John Doe',
      description: 'A test article',
    };

    it('creates episode successfully', async () => {
      mockFetch.mockResolvedValue({
        ok: true,
        json: () => Promise.resolve({ id: 'ep_abc123' }),
      });

      const result = await createEpisode('test-token', validRequest);

      expect(mockFetch).toHaveBeenCalledWith(
        `${BASE_URL}/api/v1/episodes`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer test-token',
          },
          body: JSON.stringify(validRequest),
        }
      );
      expect(result).toEqual({ success: true, data: { id: 'ep_abc123' } });
    });

    it('handles 401 unauthorized', async () => {
      mockFetch.mockResolvedValue({
        ok: false,
        status: 401,
        json: () => Promise.resolve({ error: 'Unauthorized' }),
      });

      const result = await createEpisode('invalid-token', validRequest);

      expect(result).toEqual({
        success: false,
        status: 401,
        error: 'Unauthorized',
      });
    });

    it('handles 422 validation error', async () => {
      mockFetch.mockResolvedValue({
        ok: false,
        status: 422,
        json: () => Promise.resolve({ error: 'Content is too short' }),
      });

      const result = await createEpisode('test-token', validRequest);

      expect(result).toEqual({
        success: false,
        status: 422,
        error: 'Content is too short',
      });
    });

    it('handles 429 rate limit with Retry-After header', async () => {
      mockFetch.mockResolvedValue({
        ok: false,
        status: 429,
        headers: {
          get: (name: string) => name === 'Retry-After' ? '3600' : null,
        },
        json: () => Promise.resolve({ error: 'Rate limit exceeded' }),
      });

      const result = await createEpisode('test-token', validRequest);

      expect(result).toEqual({
        success: false,
        status: 429,
        error: 'Rate limit exceeded',
        retryAfter: 3600,
      });
    });

    it('handles 429 rate limit without Retry-After header', async () => {
      mockFetch.mockResolvedValue({
        ok: false,
        status: 429,
        headers: {
          get: () => null,
        },
        json: () => Promise.resolve({ error: 'Episode limit reached' }),
      });

      const result = await createEpisode('test-token', validRequest);

      expect(result).toEqual({
        success: false,
        status: 429,
        error: 'Episode limit reached',
      });
    });

    it('uses default error message when none provided', async () => {
      mockFetch.mockResolvedValue({
        ok: false,
        status: 401,
        json: () => Promise.resolve({}),
      });

      const result = await createEpisode('test-token', validRequest);

      expect(result).toEqual({
        success: false,
        status: 401,
        error: 'Unauthorized - please reconnect the extension',
      });
    });

    it('handles network errors', async () => {
      mockFetch.mockRejectedValue(new Error('Failed to fetch'));

      const result = await createEpisode('test-token', validRequest);

      expect(result).toEqual({
        success: false,
        status: 0,
        error: 'Failed to fetch',
      });
    });

    it('handles non-Error exceptions', async () => {
      mockFetch.mockRejectedValue('Unknown error');

      const result = await createEpisode('test-token', validRequest);

      expect(result).toEqual({
        success: false,
        status: 0,
        error: 'Network error',
      });
    });
  });

  describe('logExtensionFailure', () => {
    const validRequest: LogExtensionFailureRequest = {
      url: 'https://example.com/page',
      error_type: 'extraction_failed',
      error_message: 'Could not extract article content',
    };

    it('logs failure successfully', async () => {
      mockFetch.mockResolvedValue({
        ok: true,
        json: () => Promise.resolve({ logged: true }),
      });

      const result = await logExtensionFailure('test-token', validRequest);

      expect(mockFetch).toHaveBeenCalledWith(
        `${BASE_URL}/api/v1/extension_logs`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer test-token',
          },
          body: JSON.stringify(validRequest),
        }
      );
      expect(result).toEqual({ success: true, data: { logged: true } });
    });

    it('handles errors gracefully', async () => {
      mockFetch.mockResolvedValue({
        ok: false,
        status: 500,
        json: () => Promise.resolve({ error: 'Internal server error' }),
      });

      const result = await logExtensionFailure('test-token', validRequest);

      expect(result).toEqual({
        success: false,
        status: 500,
        error: 'Internal server error',
      });
    });

    it('handles network errors', async () => {
      mockFetch.mockRejectedValue(new Error('Network unavailable'));

      const result = await logExtensionFailure('test-token', validRequest);

      expect(result).toEqual({
        success: false,
        status: 0,
        error: 'Network unavailable',
      });
    });
  });
});
