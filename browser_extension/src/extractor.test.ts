import { isArticleLike, extract, ExtractedArticle } from './extractor';

// Helper to create a mock document
function createMockDocument(html: string): Document {
  const parser = new DOMParser();
  return parser.parseFromString(html, 'text/html');
}

describe('extractor', () => {
  describe('isArticleLike', () => {
    it('returns true when page has article element', () => {
      const doc = createMockDocument('<html><body><article>Content</article></body></html>');
      expect(isArticleLike(doc)).toBe(true);
    });

    it('returns true when page has main element with sufficient content', () => {
      const words = Array(250).fill('word').join(' ');
      const doc = createMockDocument(`<html><body><main>${words}</main></body></html>`);
      expect(isArticleLike(doc)).toBe(true);
    });

    it('returns true when page has article meta tags', () => {
      const doc = createMockDocument(`
        <html>
          <head><meta property="og:type" content="article"></head>
          <body>Short content</body>
        </html>
      `);
      expect(isArticleLike(doc)).toBe(true);
    });

    it('returns true when page has author meta tag', () => {
      const doc = createMockDocument(`
        <html>
          <head><meta name="author" content="John Doe"></head>
          <body>Short content</body>
        </html>
      `);
      expect(isArticleLike(doc)).toBe(true);
    });

    it('returns true when body has 500+ words', () => {
      const words = Array(600).fill('word').join(' ');
      const doc = createMockDocument(`<html><body><div>${words}</div></body></html>`);
      expect(isArticleLike(doc)).toBe(true);
    });

    it('returns false for pages with little content', () => {
      const doc = createMockDocument('<html><body><div>Just a few words here.</div></body></html>');
      expect(isArticleLike(doc)).toBe(false);
    });

    it('returns false for empty pages', () => {
      const doc = createMockDocument('<html><body></body></html>');
      expect(isArticleLike(doc)).toBe(false);
    });
  });

  describe('extract', () => {
    it('extracts article content successfully', () => {
      const articleContent = Array(100).fill('This is article content.').join(' ');
      const doc = createMockDocument(`
        <html>
          <head><title>Test Article</title></head>
          <body>
            <article>
              <h1>Test Article</h1>
              <p class="byline">By John Doe</p>
              <p>${articleContent}</p>
            </article>
          </body>
        </html>
      `);

      const result = extract(doc, 'https://example.com/article');

      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.article.title).toBeTruthy();
        expect(result.article.content).toContain('article content');
        expect(result.article.url).toBe('https://example.com/article');
      }
    });

    it('returns error when content cannot be extracted', () => {
      const doc = createMockDocument('<html><body><nav>Menu items</nav></body></html>');

      const result = extract(doc, 'https://example.com/nav');

      expect(result.success).toBe(false);
      if (!result.success) {
        expect(result.error).toBeTruthy();
      }
    });

    it('returns error when content is too short', () => {
      const doc = createMockDocument(`
        <html>
          <body>
            <article><p>Short.</p></article>
          </body>
        </html>
      `);

      const result = extract(doc, 'https://example.com/short');

      expect(result.success).toBe(false);
      if (!result.success) {
        expect(result.error).toContain('too short');
      }
    });

    it('uses document title as fallback', () => {
      const articleContent = Array(100).fill('Content here.').join(' ');
      const doc = createMockDocument(`
        <html>
          <head><title>Page Title</title></head>
          <body>
            <article><p>${articleContent}</p></article>
          </body>
        </html>
      `);

      const result = extract(doc, 'https://example.com/article');

      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.article.title).toBeTruthy();
      }
    });
  });
});
