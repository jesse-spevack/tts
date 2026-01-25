/**
 * Message types for communication between background script and content script
 * Defines the protocol for inter-script messaging
 */

import type { ExtractedArticle } from './extractor';

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

// Re-export ExtractedArticle for consumers
export type { ExtractedArticle };
