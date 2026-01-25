/**
 * Icon state management for TTS browser extension
 * Controls the extension icon appearance based on current state
 * Uses Catppuccin colors matching the app's design system
 */

export type IconState = 'neutral' | 'loading' | 'success' | 'error' | 'offline' | 'rate_limited';

interface IconConfig {
  badgeText: string;
  badgeColor: string;
}

// Catppuccin Latte (light mode) colors
const LIGHT_COLORS = {
  green: '#40a02b',
  red: '#d20f39',
  blue: '#1e66f5',
  yellow: '#df8e1d',
  overlay: '#8c8fa1',
};

// Catppuccin Mocha (dark mode) colors
const DARK_COLORS = {
  green: '#a6e3a1',
  red: '#f38ba8',
  blue: '#89b4fa',
  yellow: '#f9e2af',
  overlay: '#6c7086',
};

function getColors(): typeof LIGHT_COLORS {
  // Detect system dark mode preference
  const isDark = globalThis.matchMedia?.('(prefers-color-scheme: dark)').matches ?? false;
  return isDark ? DARK_COLORS : LIGHT_COLORS;
}

function getIconConfigs(): Record<IconState, IconConfig> {
  const colors = getColors();

  return {
    neutral: {
      badgeText: '',
      badgeColor: colors.overlay,
    },
    loading: {
      badgeText: '...',
      badgeColor: colors.blue,
    },
    success: {
      badgeText: '✓',
      badgeColor: colors.green,
    },
    error: {
      badgeText: '!',
      badgeColor: colors.red,
    },
    offline: {
      badgeText: '○',
      badgeColor: colors.overlay,
    },
    rate_limited: {
      badgeText: '⏳',
      badgeColor: colors.yellow,
    },
  };
}

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

  const configs = getIconConfigs();
  const config = configs[state];

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
  return getIconConfigs()[state];
}
