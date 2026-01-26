/**
 * Message types for communication between background script and content script
 * Defines the protocol for inter-script messaging
 */

/**
 * Extracted article data from content script
 * Note: Defined here (not imported from extractor.ts) to avoid pulling
 * extractor dependencies into background.js service worker
 */
export interface ExtractedArticle {
  title: string;
  content: string;
  url: string;
  author?: string;
  description?: string;
}

/**
 * Request to extract article content from the current page
 */
export interface ExtractRequest {
  type: 'EXTRACT_ARTICLE';
}

/**
 * Successful extraction response with article data
 */
export interface ExtractSuccessResponse {
  success: true;
  article: ExtractedArticle;
}

/**
 * Failed extraction response with error details
 */
export interface ExtractErrorResponse {
  success: false;
  error: string;
  errorType: 'NOT_ARTICLE' | 'EXTRACTION_FAILED';
}

/**
 * Union type for all possible extraction responses
 */
export type ExtractResponse = ExtractSuccessResponse | ExtractErrorResponse;
