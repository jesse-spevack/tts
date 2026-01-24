/**
 * Article extraction module for TTS browser extension
 * Uses Mozilla Readability to extract article content
 */

import { Readability } from '@mozilla/readability';

export interface ExtractedArticle {
  title: string;
  content: string;
  url: string;
  author?: string;
  description?: string;
}

export type ExtractionResult =
  | { success: true; article: ExtractedArticle }
  | { success: false; error: string };

/**
 * Pre-check heuristics to determine if the current page is likely an article
 * Returns true if the page appears to be article-like
 */
export function isArticleLike(doc: Document): boolean {
  // Check for <article> element
  if (doc.querySelector('article')) {
    return true;
  }

  // Check for common main content selectors
  const mainContent = doc.querySelector('main, [role="main"], #main, .main-content, .post-content, .article-content, .entry-content');
  if (mainContent) {
    const wordCount = countWords(mainContent.textContent || '');
    if (wordCount >= 200) {
      return true;
    }
  }

  // Check for article meta tags
  const hasArticleMeta = !!(
    doc.querySelector('meta[property="og:type"][content="article"]') ||
    doc.querySelector('meta[property="article:published_time"]') ||
    doc.querySelector('meta[name="author"]')
  );
  if (hasArticleMeta) {
    return true;
  }

  // Fallback: check overall body text
  const bodyText = doc.body?.textContent || '';
  const wordCount = countWords(bodyText);
  
  // If the page has substantial text content, consider it article-like
  return wordCount >= 500;
}

/**
 * Extract article content from the current page
 */
export function extract(doc: Document, url: string): ExtractionResult {
  try {
    // Clone the document to avoid modifying the original
    const documentClone = doc.cloneNode(true) as Document;
    
    const reader = new Readability(documentClone);
    const article = reader.parse();

    if (!article) {
      return {
        success: false,
        error: 'Could not extract article content',
      };
    }

    if (!article.content || article.content.trim().length === 0) {
      return {
        success: false,
        error: 'Extracted content is empty',
      };
    }

    // Extract text content from HTML for the API
    const textContent = htmlToText(article.content);
    
    if (countWords(textContent) < 50) {
      return {
        success: false,
        error: 'Article content is too short',
      };
    }

    return {
      success: true,
      article: {
        title: article.title || doc.title || 'Untitled',
        content: textContent,
        url: url,
        author: article.byline || undefined,
        description: article.excerpt || undefined,
      },
    };
  } catch (error) {
    return {
      success: false,
      error: error instanceof Error ? error.message : 'Extraction failed',
    };
  }
}

/**
 * Count words in a text string
 */
function countWords(text: string): number {
  return text
    .trim()
    .split(/\s+/)
    .filter(word => word.length > 0).length;
}

/**
 * Convert HTML to plain text, preserving paragraph breaks
 */
function htmlToText(html: string): string {
  const doc = new DOMParser().parseFromString(html, 'text/html');
  
  // Replace block elements with newlines
  const blockElements = doc.querySelectorAll('p, br, div, h1, h2, h3, h4, h5, h6, li');
  blockElements.forEach(el => {
    el.insertAdjacentText('afterend', '\n\n');
  });

  return (doc.body?.textContent || '')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}
