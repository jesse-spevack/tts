// Jest setup for Chrome extension testing
// This file runs before each test file

// Create Chrome API mocks
const chromeMock = {
  runtime: {
    sendMessage: jest.fn(),
    onMessage: {
      addListener: jest.fn(),
      removeListener: jest.fn(),
    },
    getURL: jest.fn((path) => `chrome-extension://test-id/${path}`),
    lastError: null,
  },
  storage: {
    local: {
      get: jest.fn(),
      set: jest.fn(),
      remove: jest.fn(),
      clear: jest.fn(),
    },
    sync: {
      get: jest.fn(),
      set: jest.fn(),
      remove: jest.fn(),
      clear: jest.fn(),
    },
  },
  tabs: {
    query: jest.fn(),
    sendMessage: jest.fn(),
    create: jest.fn(),
    update: jest.fn(),
  },
  action: {
    setBadgeText: jest.fn(),
    setBadgeBackgroundColor: jest.fn(),
    setIcon: jest.fn(),
  },
};

// Assign chrome mock to global
global.chrome = chromeMock;
