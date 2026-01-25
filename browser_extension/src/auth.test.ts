import {
  storeToken,
  getToken,
  clearToken,
  isConnected,
  validateToken,
} from './auth';

// Valid test token matching the required format: pk_live_ + 32-64 chars
const VALID_TOKEN = 'pk_live_abcdefghij1234567890abcdefghij12';

describe('auth', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    (chrome.runtime as any).lastError = null;
  });

  describe('validateToken', () => {
    it('accepts valid pk_live_ token', () => {
      expect(() => validateToken(VALID_TOKEN)).not.toThrow();
    });

    it('accepts token with 64 character suffix', () => {
      const longToken =
        'pk_live_' + 'a'.repeat(64);
      expect(() => validateToken(longToken)).not.toThrow();
    });

    it('rejects empty string', () => {
      expect(() => validateToken('')).toThrow('Token must be a non-empty string');
    });

    it('rejects non-string values', () => {
      expect(() => validateToken(null)).toThrow('Token must be a non-empty string');
      expect(() => validateToken(undefined)).toThrow(
        'Token must be a non-empty string'
      );
      expect(() => validateToken(123)).toThrow('Token must be a non-empty string');
    });

    it('rejects token with wrong prefix', () => {
      expect(() => validateToken('tts_ext_abc123')).toThrow('Invalid token format');
      expect(() => validateToken('pk_invalid_abc123')).toThrow(
        'Invalid token format'
      );
      // pk_test_ is no longer valid
      expect(() => validateToken('pk_test_abcdefghij1234567890abcdefghij12')).toThrow(
        'Invalid token format'
      );
    });

    it('rejects token with suffix too short', () => {
      // Only 31 chars after prefix
      const shortToken = 'pk_live_' + 'a'.repeat(31);
      expect(() => validateToken(shortToken)).toThrow('Invalid token format');
    });

    it('rejects token with suffix too long', () => {
      // 65 chars after prefix
      const longToken = 'pk_live_' + 'a'.repeat(65);
      expect(() => validateToken(longToken)).toThrow('Invalid token format');
    });

    it('rejects token with invalid characters', () => {
      const invalidToken = 'pk_live_abcdefghij1234567890abcd!@#$';
      expect(() => validateToken(invalidToken)).toThrow('Invalid token format');
    });
  });

  describe('storeToken', () => {
    it('stores valid token in chrome.storage.sync', async () => {
      (chrome.storage.sync.set as jest.Mock).mockImplementation(
        (_data, callback) => {
          callback();
        }
      );

      await storeToken(VALID_TOKEN);

      expect(chrome.storage.sync.set).toHaveBeenCalledWith(
        { very_normal_tts_api_token: VALID_TOKEN },
        expect.any(Function)
      );
    });

    it('rejects invalid token format before storage', async () => {
      await expect(storeToken('invalid_token')).rejects.toThrow(
        'Invalid token format'
      );
      expect(chrome.storage.sync.set).not.toHaveBeenCalled();
    });

    it('rejects on storage error', async () => {
      (chrome.storage.sync.set as jest.Mock).mockImplementation(
        (_data, callback) => {
          (chrome.runtime as any).lastError = {
            message: 'Storage quota exceeded',
          };
          callback();
          (chrome.runtime as any).lastError = null;
        }
      );

      await expect(storeToken(VALID_TOKEN)).rejects.toThrow(
        'Storage quota exceeded'
      );
    });
  });

  describe('getToken', () => {
    it('returns token when stored', async () => {
      (chrome.storage.sync.get as jest.Mock).mockImplementation(
        (_keys, callback) => {
          callback({ very_normal_tts_api_token: VALID_TOKEN });
        }
      );

      const token = await getToken();

      expect(chrome.storage.sync.get).toHaveBeenCalledWith(
        ['very_normal_tts_api_token'],
        expect.any(Function)
      );
      expect(token).toBe(VALID_TOKEN);
    });

    it('returns null when no token stored', async () => {
      (chrome.storage.sync.get as jest.Mock).mockImplementation(
        (_keys, callback) => {
          callback({});
        }
      );

      const token = await getToken();

      expect(token).toBeNull();
    });

    it('rejects on storage error', async () => {
      (chrome.storage.sync.get as jest.Mock).mockImplementation(
        (_keys, callback) => {
          (chrome.runtime as any).lastError = { message: 'Storage unavailable' };
          callback({});
          (chrome.runtime as any).lastError = null;
        }
      );

      await expect(getToken()).rejects.toThrow('Storage unavailable');
    });
  });

  describe('clearToken', () => {
    it('removes token from chrome.storage.sync', async () => {
      (chrome.storage.sync.remove as jest.Mock).mockImplementation(
        (_keys, callback) => {
          callback();
        }
      );

      await clearToken();

      expect(chrome.storage.sync.remove).toHaveBeenCalledWith(
        ['very_normal_tts_api_token'],
        expect.any(Function)
      );
    });

    it('rejects on storage error', async () => {
      (chrome.storage.sync.remove as jest.Mock).mockImplementation(
        (_keys, callback) => {
          (chrome.runtime as any).lastError = { message: 'Remove failed' };
          callback();
          (chrome.runtime as any).lastError = null;
        }
      );

      await expect(clearToken()).rejects.toThrow('Remove failed');
    });
  });

  describe('isConnected', () => {
    it('returns true when token exists', async () => {
      (chrome.storage.sync.get as jest.Mock).mockImplementation(
        (_keys, callback) => {
          callback({ very_normal_tts_api_token: VALID_TOKEN });
        }
      );

      const connected = await isConnected();

      expect(connected).toBe(true);
    });

    it('returns false when no token exists', async () => {
      (chrome.storage.sync.get as jest.Mock).mockImplementation(
        (_keys, callback) => {
          callback({});
        }
      );

      const connected = await isConnected();

      expect(connected).toBe(false);
    });
  });
});
