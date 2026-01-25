/**
 * Context menu management for TTS browser extension
 * Handles right-click menu on extension icon (e.g., disconnect option)
 */

import { clearToken } from './auth';
import { setIconState } from './icons';

/**
 * Menu item IDs for context menu actions
 */
export const MENU_ITEMS = {
  DISCONNECT: 'disconnect',
} as const;

/**
 * Initialize context menu items
 * Called on extension installation
 */
export function setupContextMenu(): void {
  // Create context menu item for disconnecting (appears when right-clicking extension icon)
  chrome.contextMenus.create({
    id: MENU_ITEMS.DISCONNECT,
    title: 'Disconnect from TTS',
    contexts: ['action'],
  });
}

/**
 * Handle context menu item clicks
 */
export async function handleContextMenuClick(
  info: chrome.contextMenus.OnClickData
): Promise<void> {
  if (info.menuItemId === MENU_ITEMS.DISCONNECT) {
    await clearToken();
    await setIconState('neutral');
    console.log('TTS Extension: Disconnected');
  }
}

/**
 * Register context menu event listeners
 */
export function registerContextMenuListeners(): void {
  chrome.contextMenus.onClicked.addListener(handleContextMenuClick);
}
