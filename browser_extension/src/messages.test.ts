/**
 * Tests for message types module
 * Verifies type exports and interface structure
 */

import type {
  ExtractRequest,
  ExtractSuccessResponse,
  ExtractErrorResponse,
  ExtractResponse,
  ExtractedArticle,
} from './messages';

describe('messages types', () => {
  describe('ExtractRequest', () => {
    it('should have EXTRACT_ARTICLE type', () => {
      const request: ExtractRequest = { type: 'EXTRACT_ARTICLE' };
      expect(request.type).toBe('EXTRACT_ARTICLE');
    });
  });

  describe('ExtractSuccessResponse', () => {
    it('should have success: true and article', () => {
      const article: ExtractedArticle = {
        title: 'Test Article',
        content: 'Test content',
        url: 'https://example.com/article',
        author: 'Test Author',
        description: 'Test description',
      };

      const response: ExtractSuccessResponse = {
        success: true,
        article,
      };

      expect(response.success).toBe(true);
      expect(response.article).toEqual(article);
    });

    it('should allow optional author and description', () => {
      const article: ExtractedArticle = {
        title: 'Test Article',
        content: 'Test content',
        url: 'https://example.com/article',
      };

      const response: ExtractSuccessResponse = {
        success: true,
        article,
      };

      expect(response.article.author).toBeUndefined();
      expect(response.article.description).toBeUndefined();
    });
  });

  describe('ExtractErrorResponse', () => {
    it('should have success: false with NOT_ARTICLE error type', () => {
      const response: ExtractErrorResponse = {
        success: false,
        error: 'This page does not appear to be an article',
        errorType: 'NOT_ARTICLE',
      };

      expect(response.success).toBe(false);
      expect(response.errorType).toBe('NOT_ARTICLE');
    });

    it('should have success: false with EXTRACTION_FAILED error type', () => {
      const response: ExtractErrorResponse = {
        success: false,
        error: 'Could not extract article content',
        errorType: 'EXTRACTION_FAILED',
      };

      expect(response.success).toBe(false);
      expect(response.errorType).toBe('EXTRACTION_FAILED');
    });
  });

  describe('ExtractResponse union type', () => {
    it('should narrow correctly based on success field', () => {
      const successResponse: ExtractResponse = {
        success: true,
        article: {
          title: 'Test',
          content: 'Content',
          url: 'https://example.com',
        },
      };

      const errorResponse: ExtractResponse = {
        success: false,
        error: 'Error message',
        errorType: 'NOT_ARTICLE',
      };

      // Type narrowing test
      if (successResponse.success) {
        expect(successResponse.article.title).toBe('Test');
      }

      if (!errorResponse.success) {
        expect(errorResponse.errorType).toBe('NOT_ARTICLE');
      }
    });
  });
});
