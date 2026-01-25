/**
 * Tests for context menu module
 */

import { MENU_ITEMS, setupContextMenu, handleContextMenuClick, registerContextMenuListeners } from './contextMenu';
import * as auth from './auth';
import * as icons from './icons';

// Mock the dependencies
jest.mock('./auth');
jest.mock('./icons');

const mockAuth = auth as jest.Mocked<typeof auth>;
const mockIcons = icons as jest.Mocked<typeof icons>;

// Create contextMenus mock
const mockContextMenus = {
  create: jest.fn(),
  onClicked: {
    addListener: jest.fn(),
  },
};

// Add contextMenus to chrome mock
beforeAll(() => {
  (global.chrome as unknown as Record<string, unknown>).contextMenus = mockContextMenus;
});

describe('contextMenu', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockIcons.setIconState.mockResolvedValue(undefined);
    mockAuth.clearToken.mockResolvedValue(undefined);
  });

  describe('MENU_ITEMS', () => {
    it('should have DISCONNECT menu item', () => {
      expect(MENU_ITEMS.DISCONNECT).toBe('disconnect');
    });
  });

  describe('setupContextMenu', () => {
    it('should create disconnect menu item', () => {
      setupContextMenu();

      expect(mockContextMenus.create).toHaveBeenCalledWith({
        id: 'disconnect',
        title: 'Disconnect from TTS',
        contexts: ['action'],
      });
    });
  });

  describe('handleContextMenuClick', () => {
    it('should clear token and reset icon when disconnect is clicked', async () => {
      const info: chrome.contextMenus.OnClickData = {
        menuItemId: 'disconnect',
        editable: false,
        pageUrl: 'https://example.com',
      };

      await handleContextMenuClick(info);

      expect(mockAuth.clearToken).toHaveBeenCalled();
      expect(mockIcons.setIconState).toHaveBeenCalledWith('neutral');
    });

    it('should ignore other menu item clicks', async () => {
      const info: chrome.contextMenus.OnClickData = {
        menuItemId: 'other-item',
        editable: false,
        pageUrl: 'https://example.com',
      };

      await handleContextMenuClick(info);

      expect(mockAuth.clearToken).not.toHaveBeenCalled();
      expect(mockIcons.setIconState).not.toHaveBeenCalled();
    });
  });

  describe('registerContextMenuListeners', () => {
    it('should register click handler', () => {
      registerContextMenuListeners();

      expect(mockContextMenus.onClicked.addListener).toHaveBeenCalledWith(handleContextMenuClick);
    });
  });
});
