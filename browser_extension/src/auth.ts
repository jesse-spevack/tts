/**
 * Token storage and authentication module for the TTS browser extension
 * Uses chrome.storage.sync to persist the API token across devices
 */

const TOKEN_KEY = 'very_normal_tts_api_token';

/**
 * Valid token format: pk_live_* or pk_test_* followed by 32-64 alphanumeric chars
 */
const TOKEN_PATTERN = /^pk_(live|test)_[a-zA-Z0-9_-]{32,64}$/;

/**
 * Validate token format before storage
 * @throws Error if token is invalid
 */
export function validateToken(token: unknown): asserts token is string {
  if (typeof token !== 'string' || token.length === 0) {
    throw new Error('Token must be a non-empty string');
  }
  if (!TOKEN_PATTERN.test(token)) {
    throw new Error(
      'Invalid token format. Expected pk_live_* or pk_test_* with 32-64 character suffix'
    );
  }
}

/**
 * Store the API token in chrome.storage.sync
 * @throws Error if token format is invalid
 */
export async function storeToken(token: string): Promise<void> {
  validateToken(token);

  return new Promise((resolve, reject) => {
    chrome.storage.sync.set({ [TOKEN_KEY]: token }, () => {
      if (chrome.runtime.lastError) {
        reject(new Error(chrome.runtime.lastError.message));
      } else {
        resolve();
      }
    });
  });
}

/**
 * Retrieve the API token from chrome.storage.sync
 * Returns null if no token is stored
 */
export async function getToken(): Promise<string | null> {
  return new Promise((resolve, reject) => {
    chrome.storage.sync.get([TOKEN_KEY], (result) => {
      if (chrome.runtime.lastError) {
        reject(new Error(chrome.runtime.lastError.message));
      } else {
        resolve(result[TOKEN_KEY] || null);
      }
    });
  });
}

/**
 * Clear the API token from chrome.storage.sync
 * Used when disconnecting the extension
 */
export async function clearToken(): Promise<void> {
  return new Promise((resolve, reject) => {
    chrome.storage.sync.remove([TOKEN_KEY], () => {
      if (chrome.runtime.lastError) {
        reject(new Error(chrome.runtime.lastError.message));
      } else {
        resolve();
      }
    });
  });
}

/**
 * Check if the extension is connected (has a stored token)
 */
export async function isConnected(): Promise<boolean> {
  const token = await getToken();
  return token !== null;
}
