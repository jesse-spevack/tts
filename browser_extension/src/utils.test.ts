import { isValidArticleUrl, sendToBackground } from './utils';

describe('isValidArticleUrl', () => {
  it('returns true for valid http URLs', () => {
    expect(isValidArticleUrl('http://example.com/article')).toBe(true);
  });

  it('returns true for valid https URLs', () => {
    expect(isValidArticleUrl('https://example.com/article')).toBe(true);
  });

  it('returns false for invalid URLs', () => {
    expect(isValidArticleUrl('not-a-url')).toBe(false);
  });

  it('returns false for non-http protocols', () => {
    expect(isValidArticleUrl('file:///path/to/file')).toBe(false);
    expect(isValidArticleUrl('chrome://extensions')).toBe(false);
  });
});

describe('sendToBackground', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('sends message to background script', async () => {
    const mockResponse = { success: true };
    (chrome.runtime.sendMessage as jest.Mock).mockImplementation(
      (_message, callback) => {
        callback(mockResponse);
      }
    );

    const result = await sendToBackground('test', { data: 'value' });

    expect(chrome.runtime.sendMessage).toHaveBeenCalledWith(
      { action: 'test', data: 'value' },
      expect.any(Function)
    );
    expect(result).toEqual(mockResponse);
  });

  it('rejects on runtime error', async () => {
    (chrome.runtime.sendMessage as jest.Mock).mockImplementation(
      (_message, callback) => {
        (chrome.runtime as any).lastError = { message: 'Test error' };
        callback(undefined);
        (chrome.runtime as any).lastError = null;
      }
    );

    await expect(sendToBackground('test', {})).rejects.toThrow('Test error');
  });
});
