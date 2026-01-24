/**
 * Token storage and authentication module for the TTS browser extension
 * Uses chrome.storage.sync to persist the API token across devices
 */

const TOKEN_KEY = 'tts_api_token';

/**
 * Store the API token in chrome.storage.sync
 */
export async function storeToken(token: string): Promise<void> {
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
