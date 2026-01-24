import { setIconState, getIconConfig, IconState } from './icons';

describe('icons', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    jest.useFakeTimers();
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  describe('getIconConfig', () => {
    it('returns config for neutral state', () => {
      const config = getIconConfig('neutral');
      expect(config.badgeText).toBe('');
      expect(config.badgeColor).toBeTruthy();
    });

    it('returns config for loading state', () => {
      const config = getIconConfig('loading');
      expect(config.badgeText).toBe('...');
      expect(config.badgeColor).toBe('#1e66f5'); // Catppuccin blue
    });

    it('returns config for success state', () => {
      const config = getIconConfig('success');
      expect(config.badgeText).toBe('✓');
      expect(config.badgeColor).toBe('#40a02b'); // Catppuccin green
    });

    it('returns config for error state', () => {
      const config = getIconConfig('error');
      expect(config.badgeText).toBe('!');
      expect(config.badgeColor).toBe('#d20f39'); // Catppuccin red
    });

    it('returns config for offline state', () => {
      const config = getIconConfig('offline');
      expect(config.badgeText).toBe('○');
      expect(config.badgeColor).toBe('#8c8fa1'); // Catppuccin overlay1
    });

    it('returns config for rate_limited state', () => {
      const config = getIconConfig('rate_limited');
      expect(config.badgeText).toBe('⏳');
      expect(config.badgeColor).toBe('#df8e1d'); // Catppuccin yellow
    });
  });

  describe('setIconState', () => {
    beforeEach(() => {
      (chrome.action.setBadgeText as jest.Mock).mockImplementation(
        (_opts, callback) => callback?.()
      );
      (chrome.action.setBadgeBackgroundColor as jest.Mock).mockImplementation(
        (_opts, callback) => callback?.()
      );
    });

    it('sets badge text and color for neutral state', async () => {
      await setIconState('neutral');

      expect(chrome.action.setBadgeText).toHaveBeenCalledWith(
        { text: '' },
        expect.any(Function)
      );
      expect(chrome.action.setBadgeBackgroundColor).toHaveBeenCalledWith(
        { color: '#8c8fa1' }, // Catppuccin overlay1
        expect.any(Function)
      );
    });

    it('sets badge text and color for loading state', async () => {
      await setIconState('loading');

      expect(chrome.action.setBadgeText).toHaveBeenCalledWith(
        { text: '...' },
        expect.any(Function)
      );
      expect(chrome.action.setBadgeBackgroundColor).toHaveBeenCalledWith(
        { color: '#1e66f5' }, // Catppuccin blue
        expect.any(Function)
      );
    });

    it('auto-reverts success state to neutral after delay', async () => {
      await setIconState('success');

      expect(chrome.action.setBadgeText).toHaveBeenCalledWith(
        { text: '✓' },
        expect.any(Function)
      );

      // Fast-forward past the auto-revert delay
      jest.advanceTimersByTime(2500);

      // Should have been called again with neutral state
      expect(chrome.action.setBadgeText).toHaveBeenLastCalledWith(
        { text: '' },
        expect.any(Function)
      );
    });

    it('auto-reverts error state to neutral after delay', async () => {
      await setIconState('error');

      expect(chrome.action.setBadgeText).toHaveBeenCalledWith(
        { text: '!' },
        expect.any(Function)
      );

      // Fast-forward past the auto-revert delay
      jest.advanceTimersByTime(2500);

      // Should have been called again with neutral state
      expect(chrome.action.setBadgeText).toHaveBeenLastCalledWith(
        { text: '' },
        expect.any(Function)
      );
    });

    it('does not auto-revert loading state', async () => {
      await setIconState('loading');

      const callCount = (chrome.action.setBadgeText as jest.Mock).mock.calls.length;

      // Fast-forward past the auto-revert delay
      jest.advanceTimersByTime(5000);

      // Should not have been called again
      expect(chrome.action.setBadgeText).toHaveBeenCalledTimes(callCount);
    });

    it('cancels pending revert when state changes', async () => {
      await setIconState('success');
      
      // Change state before auto-revert
      jest.advanceTimersByTime(1000);
      await setIconState('loading');

      // Fast-forward past original auto-revert time
      jest.advanceTimersByTime(2000);

      // Should still be in loading state (not reverted to neutral)
      expect(chrome.action.setBadgeText).toHaveBeenLastCalledWith(
        { text: '...' },
        expect.any(Function)
      );
    });
  });
});
