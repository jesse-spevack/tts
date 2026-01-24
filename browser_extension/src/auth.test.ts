import { storeToken, getToken, clearToken, isConnected } from './auth';

describe('auth', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    (chrome.runtime as any).lastError = null;
  });

  describe('storeToken', () => {
    it('stores token in chrome.storage.sync', async () => {
      (chrome.storage.sync.set as jest.Mock).mockImplementation(
        (_data, callback) => {
          callback();
        }
      );

      await storeToken('tts_ext_abc123');

      expect(chrome.storage.sync.set).toHaveBeenCalledWith(
        { tts_api_token: 'tts_ext_abc123' },
        expect.any(Function)
      );
    });

    it('rejects on storage error', async () => {
      (chrome.storage.sync.set as jest.Mock).mockImplementation(
        (_data, callback) => {
          (chrome.runtime as any).lastError = { message: 'Storage quota exceeded' };
          callback();
          (chrome.runtime as any).lastError = null;
        }
      );

      await expect(storeToken('tts_ext_abc123')).rejects.toThrow(
        'Storage quota exceeded'
      );
    });
  });

  describe('getToken', () => {
    it('returns token when stored', async () => {
      (chrome.storage.sync.get as jest.Mock).mockImplementation(
        (_keys, callback) => {
          callback({ tts_api_token: 'tts_ext_stored_token' });
        }
      );

      const token = await getToken();

      expect(chrome.storage.sync.get).toHaveBeenCalledWith(
        ['tts_api_token'],
        expect.any(Function)
      );
      expect(token).toBe('tts_ext_stored_token');
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
        ['tts_api_token'],
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
          callback({ tts_api_token: 'tts_ext_some_token' });
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
