import {
  shouldDebounce,
  recordSuccessfulSend,
  clearDebounceState,
  getDebounceWindowMs,
} from './debounce';

describe('debounce', () => {
  beforeEach(() => {
    clearDebounceState();
    jest.useFakeTimers();
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  describe('shouldDebounce', () => {
    it('returns false when no previous send recorded', () => {
      expect(shouldDebounce('https://example.com/article')).toBe(false);
    });

    it('returns true for same URL within debounce window', () => {
      const url = 'https://example.com/article';
      recordSuccessfulSend(url);

      expect(shouldDebounce(url)).toBe(true);
    });

    it('returns false for different URL even within debounce window', () => {
      recordSuccessfulSend('https://example.com/article1');

      expect(shouldDebounce('https://example.com/article2')).toBe(false);
    });

    it('returns false for same URL after debounce window expires', () => {
      const url = 'https://example.com/article';
      recordSuccessfulSend(url);

      // Advance time past debounce window
      jest.advanceTimersByTime(getDebounceWindowMs() + 1);

      expect(shouldDebounce(url)).toBe(false);
    });

    it('returns true for same URL just before debounce window expires', () => {
      const url = 'https://example.com/article';
      recordSuccessfulSend(url);

      // Advance time to just before window expires
      jest.advanceTimersByTime(getDebounceWindowMs() - 1);

      expect(shouldDebounce(url)).toBe(true);
    });
  });

  describe('recordSuccessfulSend', () => {
    it('updates the last successful send', () => {
      const url1 = 'https://example.com/article1';
      const url2 = 'https://example.com/article2';

      recordSuccessfulSend(url1);
      expect(shouldDebounce(url1)).toBe(true);
      expect(shouldDebounce(url2)).toBe(false);

      recordSuccessfulSend(url2);
      expect(shouldDebounce(url1)).toBe(false);
      expect(shouldDebounce(url2)).toBe(true);
    });
  });

  describe('clearDebounceState', () => {
    it('clears the recorded send', () => {
      const url = 'https://example.com/article';
      recordSuccessfulSend(url);
      expect(shouldDebounce(url)).toBe(true);

      clearDebounceState();
      expect(shouldDebounce(url)).toBe(false);
    });
  });

  describe('debounce window', () => {
    it('has a 5-second debounce window', () => {
      expect(getDebounceWindowMs()).toBe(5000);
    });
  });
});
