/**
 * Icon state management for TTS browser extension
 * Controls the extension icon appearance based on current state
 */

export type IconState = 'neutral' | 'loading' | 'success' | 'error' | 'offline';

interface IconConfig {
  badgeText: string;
  badgeColor: string;
}

const ICON_CONFIGS: Record<IconState, IconConfig> = {
  neutral: {
    badgeText: '',
    badgeColor: '#666666',
  },
  loading: {
    badgeText: '...',
    badgeColor: '#2196F3', // Blue
  },
  success: {
    badgeText: '✓',
    badgeColor: '#4CAF50', // Green
  },
  error: {
    badgeText: '!',
    badgeColor: '#F44336', // Red
  },
  offline: {
    badgeText: '○',
    badgeColor: '#9E9E9E', // Gray
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

  // Auto-revert success and error states
  if (state === 'success' || state === 'error') {
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
