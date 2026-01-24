/**
 * Icon state management for TTS browser extension
 * Controls the extension icon appearance based on current state
 */

export type IconState = 'neutral' | 'loading' | 'success' | 'error' | 'offline' | 'rate_limited';

interface IconConfig {
  badgeText: string;
  badgeColor: string;
}

// Catppuccin Latte colors for badge visibility
const ICON_CONFIGS: Record<IconState, IconConfig> = {
  neutral: {
    badgeText: '',
    badgeColor: '#8c8fa1', // Catppuccin overlay1
  },
  loading: {
    badgeText: '...',
    badgeColor: '#1e66f5', // Catppuccin blue
  },
  success: {
    badgeText: '✓',
    badgeColor: '#40a02b', // Catppuccin green
  },
  error: {
    badgeText: '!',
    badgeColor: '#d20f39', // Catppuccin red
  },
  offline: {
    badgeText: '○',
    badgeColor: '#8c8fa1', // Catppuccin overlay1
  },
  rate_limited: {
    badgeText: '⏳',
    badgeColor: '#df8e1d', // Catppuccin yellow
  },
};

// Auto-revert delay in milliseconds
const AUTO_REVERT_DELAY = 2500;

// Track pending revert timeouts
let revertTimeout: ReturnType<typeof setTimeout> | null = null;

/**
 * Set the extension icon state
 * Success and error states will auto-revert to neutral after a delay
 */
export async function setIconState(state: IconState): Promise<void> {
  // Clear any pending revert
  if (revertTimeout) {
    clearTimeout(revertTimeout);
    revertTimeout = null;
  }

  const config = ICON_CONFIGS[state];

  await Promise.all([
    setBadgeText(config.badgeText),
    setBadgeBackgroundColor(config.badgeColor),
  ]);

  // Auto-revert success, error, and rate_limited states
  if (state === 'success' || state === 'error' || state === 'rate_limited') {
    revertTimeout = setTimeout(() => {
      setIconState('neutral');
    }, AUTO_REVERT_DELAY);
  }
}

/**
 * Set badge text (wrapper for chrome.action.setBadgeText)
 */
function setBadgeText(text: string): Promise<void> {
  return new Promise((resolve) => {
    chrome.action.setBadgeText({ text }, resolve);
  });
}

/**
 * Set badge background color (wrapper for chrome.action.setBadgeBackgroundColor)
 */
function setBadgeBackgroundColor(color: string): Promise<void> {
  return new Promise((resolve) => {
    chrome.action.setBadgeBackgroundColor({ color }, resolve);
  });
}

/**
 * Get the current icon configuration for a state (for testing)
 */
export function getIconConfig(state: IconState): IconConfig {
  return ICON_CONFIGS[state];
}
