/**
 * Popup UI for TTS browser extension
 * Handles connect/disconnect flow
 */

import { isConnected, clearToken } from './auth';

const TTS_AUTH_URL = 'https://www.verynormal.fyi/api/v1/extension_token';

/**
 * Initialize the popup
 */
async function init(): Promise<void> {
  const app = document.getElementById('app');
  if (!app) return;

  const connected = await isConnected();

  if (connected) {
    renderConnectedState(app);
  } else {
    renderDisconnectedState(app);
  }
}

/**
 * Render UI for connected state
 */
function renderConnectedState(container: HTMLElement): void {
  container.innerHTML = `
    <div style="text-align: center;">
      <div style="margin-bottom: 16px;">
        <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="#4CAF50" stroke-width="2">
          <path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/>
          <polyline points="22 4 12 14.01 9 11.01"/>
        </svg>
      </div>
      <h2 style="margin: 0 0 8px; font-size: 18px; color: #333;">Connected</h2>
      <p style="margin: 0 0 16px; color: #666; font-size: 14px;">
        Click the extension icon on any article to send it to your podcast.
      </p>
      <button id="disconnect-btn" style="
        background: transparent;
        border: 1px solid #ccc;
        padding: 8px 16px;
        border-radius: 4px;
        cursor: pointer;
        font-size: 14px;
        color: #666;
      ">
        Disconnect
      </button>
    </div>
  `;

  const disconnectBtn = document.getElementById('disconnect-btn');
  disconnectBtn?.addEventListener('click', handleDisconnect);
}

/**
 * Render UI for disconnected state
 */
function renderDisconnectedState(container: HTMLElement): void {
  container.innerHTML = `
    <div style="text-align: center;">
      <div style="margin-bottom: 16px;">
        <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="#2196F3" stroke-width="2">
          <path d="M12 2L2 7l10 5 10-5-10-5z"/>
          <path d="M2 17l10 5 10-5"/>
          <path d="M2 12l10 5 10-5"/>
        </svg>
      </div>
      <h2 style="margin: 0 0 8px; font-size: 18px; color: #333;">TTS Podcast</h2>
      <p style="margin: 0 0 16px; color: #666; font-size: 14px;">
        Connect to send articles to your podcast feed.
      </p>
      <button id="connect-btn" style="
        background: #2196F3;
        color: white;
        border: none;
        padding: 12px 24px;
        border-radius: 4px;
        cursor: pointer;
        font-size: 14px;
        font-weight: 500;
      ">
        Connect to TTS
      </button>
    </div>
  `;

  const connectBtn = document.getElementById('connect-btn');
  connectBtn?.addEventListener('click', handleConnect);
}

/**
 * Handle connect button click
 * Opens TTS auth page which will trigger token generation
 */
async function handleConnect(): Promise<void> {
  // Open TTS auth page in a new tab
  // The page will handle authentication and call back to store the token
  chrome.tabs.create({ url: TTS_AUTH_URL });
  window.close();
}

/**
 * Handle disconnect button click
 */
async function handleDisconnect(): Promise<void> {
  const confirmDisconnect = confirm('Are you sure you want to disconnect?');
  if (!confirmDisconnect) return;

  await clearToken();

  const app = document.getElementById('app');
  if (app) {
    renderDisconnectedState(app);
  }
}

// Initialize when DOM is ready
document.addEventListener('DOMContentLoaded', init);
