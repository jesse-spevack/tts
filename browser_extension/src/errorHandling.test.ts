/**
 * Tests for error handling module
 */

import { isNetworkError, handleApiError, handleExtractionError, handleExtensionError } from './errorHandling';
import * as auth from './auth';
import * as icons from './icons';
import * as api from './api';

// Mock the dependencies
jest.mock('./auth');
jest.mock('./icons');
jest.mock('./api');

const mockAuth = auth as jest.Mocked<typeof auth>;
const mockIcons = icons as jest.Mocked<typeof icons>;
const mockApi = api as jest.Mocked<typeof api>;

describe('errorHandling', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockIcons.setIconState.mockResolvedValue(undefined);
    mockAuth.clearToken.mockResolvedValue(undefined);
    mockAuth.getToken.mockResolvedValue('pk_live_test1234567890123456789012345678');
    mockApi.logExtensionFailure.mockResolvedValue({ success: true, data: { logged: true } });
  });

  describe('isNetworkError', () => {
    it('should return true for "Failed to fetch" errors', () => {
      const error = new Error('Failed to fetch');
      expect(isNetworkError(error)).toBe(true);
    });

    it('should return true for "NetworkError" errors', () => {
      const error = new Error('NetworkError when attempting to fetch');
      expect(isNetworkError(error)).toBe(true);
    });

    it('should return true for "net::ERR_" errors', () => {
      const error = new Error('net::ERR_CONNECTION_REFUSED');
      expect(isNetworkError(error)).toBe(true);
    });

    it('should return true for "TypeError: Failed to fetch" errors', () => {
      const error = new Error('TypeError: Failed to fetch');
      expect(isNetworkError(error)).toBe(true);
    });

    it('should return true for errors with NetworkError name', () => {
      const error = new Error('Some message');
      error.name = 'NetworkError';
      expect(isNetworkError(error)).toBe(true);
    });

    it('should return false for other errors', () => {
      const error = new Error('Some other error');
      expect(isNetworkError(error)).toBe(false);
    });

    it('should return false for null message', () => {
      const error = new Error();
      expect(isNetworkError(error)).toBe(false);
    });
  });

  describe('handleApiError', () => {
    const url = 'https://example.com/article';
    const token = 'pk_live_test1234567890123456789012345678';

    it('should clear token and show error for 401', async () => {
      await handleApiError(401, 'Unauthorized', url, token);

      expect(mockAuth.clearToken).toHaveBeenCalled();
      expect(mockIcons.setIconState).toHaveBeenCalledWith('error');
      expect(mockApi.logExtensionFailure).not.toHaveBeenCalled();
    });

    it('should show rate_limited state for 429', async () => {
      await handleApiError(429, 'Rate limited', url, token);

      expect(mockIcons.setIconState).toHaveBeenCalledWith('rate_limited');
      expect(mockAuth.clearToken).not.toHaveBeenCalled();
      expect(mockApi.logExtensionFailure).not.toHaveBeenCalled();
    });

    it('should show offline state for status 0', async () => {
      await handleApiError(0, 'Network error', url, token);

      expect(mockIcons.setIconState).toHaveBeenCalledWith('offline');
      expect(mockApi.logExtensionFailure).not.toHaveBeenCalled();
    });

    it('should show error and log for 500+ errors', async () => {
      await handleApiError(500, 'Internal server error', url, token);

      expect(mockIcons.setIconState).toHaveBeenCalledWith('error');
      expect(mockApi.logExtensionFailure).toHaveBeenCalledWith(token, {
        url,
        error_type: 'SERVER_ERROR',
        error_message: 'Internal server error',
      });
    });

    it('should show error and log for 4xx errors (except 401, 429)', async () => {
      await handleApiError(422, 'Invalid content', url, token);

      expect(mockIcons.setIconState).toHaveBeenCalledWith('error');
      expect(mockApi.logExtensionFailure).toHaveBeenCalledWith(token, {
        url,
        error_type: 'API_ERROR',
        error_message: 'Invalid content',
      });
    });

    it('should ignore logging failures silently', async () => {
      mockApi.logExtensionFailure.mockRejectedValue(new Error('Logging failed'));

      // Should not throw
      await expect(handleApiError(500, 'Server error', url, token)).resolves.not.toThrow();
      expect(mockIcons.setIconState).toHaveBeenCalledWith('error');
    });
  });

  describe('handleExtractionError', () => {
    const url = 'https://example.com/article';

    it('should set error state and log the error', async () => {
      await handleExtractionError('Not an article', 'NOT_ARTICLE', url);

      expect(mockIcons.setIconState).toHaveBeenCalledWith('error');
      expect(mockApi.logExtensionFailure).toHaveBeenCalledWith(
        expect.any(String),
        {
          url,
          error_type: 'NOT_ARTICLE',
          error_message: 'Not an article',
        }
      );
    });

    it('should not log if no token available', async () => {
      mockAuth.getToken.mockResolvedValue(null);

      await handleExtractionError('Error', 'EXTRACTION_FAILED', url);

      expect(mockIcons.setIconState).toHaveBeenCalledWith('error');
      expect(mockApi.logExtensionFailure).not.toHaveBeenCalled();
    });

    it('should ignore logging failures silently', async () => {
      mockApi.logExtensionFailure.mockRejectedValue(new Error('Logging failed'));

      await expect(handleExtractionError('Error', 'NOT_ARTICLE', url)).resolves.not.toThrow();
    });
  });

  describe('handleExtensionError', () => {
    const url = 'https://example.com/article';

    it('should show offline state for network errors', async () => {
      const error = new Error('Failed to fetch');

      await handleExtensionError(error, url);

      expect(mockIcons.setIconState).toHaveBeenCalledWith('offline');
    });

    it('should show error state for other errors', async () => {
      const error = new Error('Some other error');

      await handleExtensionError(error, url);

      expect(mockIcons.setIconState).toHaveBeenCalledWith('error');
    });

    it('should log extension errors', async () => {
      const error = new Error('Extension crashed');

      await handleExtensionError(error, url);

      expect(mockApi.logExtensionFailure).toHaveBeenCalledWith(
        expect.any(String),
        {
          url,
          error_type: 'EXTENSION_ERROR',
          error_message: 'Extension crashed',
        }
      );
    });

    it('should handle non-Error objects', async () => {
      await handleExtensionError('string error', url);

      expect(mockIcons.setIconState).toHaveBeenCalledWith('error');
      expect(mockApi.logExtensionFailure).toHaveBeenCalledWith(
        expect.any(String),
        expect.objectContaining({
          error_message: 'Unknown error',
        })
      );
    });

    it('should not log if no token available', async () => {
      mockAuth.getToken.mockResolvedValue(null);

      await handleExtensionError(new Error('Test'), url);

      expect(mockApi.logExtensionFailure).not.toHaveBeenCalled();
    });

    it('should ignore logging failures silently', async () => {
      mockApi.logExtensionFailure.mockRejectedValue(new Error('Logging failed'));

      await expect(handleExtensionError(new Error('Test'), url)).resolves.not.toThrow();
    });
  });
});
