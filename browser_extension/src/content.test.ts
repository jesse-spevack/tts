import { isTrustedDomain, TRUSTED_DOMAINS } from './content';

describe('content', () => {
  describe('TRUSTED_DOMAINS', () => {
    it('includes podread.app', () => {
      expect(TRUSTED_DOMAINS).toContain('podread.app');
    });

    it('includes localhost', () => {
      expect(TRUSTED_DOMAINS).toContain('localhost');
    });

    it('has exactly 2 trusted domains', () => {
      expect(TRUSTED_DOMAINS).toHaveLength(2);
    });
  });

  describe('isTrustedDomain', () => {
    describe('accepts trusted domains', () => {
      it('accepts podread.app', () => {
        expect(isTrustedDomain('podread.app')).toBe(true);
      });

      it('accepts localhost', () => {
        expect(isTrustedDomain('localhost')).toBe(true);
      });
    });

    describe('accepts subdomains of trusted domains', () => {
      it('accepts www.podread.app', () => {
        expect(isTrustedDomain('www.podread.app')).toBe(true);
      });

      it('accepts staging.podread.app', () => {
        expect(isTrustedDomain('staging.podread.app')).toBe(true);
      });

      it('accepts api.podread.app', () => {
        expect(isTrustedDomain('api.podread.app')).toBe(true);
      });
    });

    describe('rejects untrusted domains', () => {
      it('rejects example.com', () => {
        expect(isTrustedDomain('example.com')).toBe(false);
      });

      it('rejects google.com', () => {
        expect(isTrustedDomain('google.com')).toBe(false);
      });

      it('rejects evil.com', () => {
        expect(isTrustedDomain('evil.com')).toBe(false);
      });

      it('rejects domains that contain trusted domain as substring', () => {
        // notpodread.app should NOT be trusted (doesn't end with .podread.app)
        expect(isTrustedDomain('notpodread.app')).toBe(false);
      });

      it('rejects domains with trusted domain in path-like position', () => {
        expect(isTrustedDomain('evil.com.podread.app.attacker.com')).toBe(false);
      });

      it('rejects empty string', () => {
        expect(isTrustedDomain('')).toBe(false);
      });

      it('rejects domains that start with trusted domain', () => {
        // podread.app.evil.com should NOT be trusted
        expect(isTrustedDomain('podread.app.evil.com')).toBe(false);
      });
    });

    describe('edge cases', () => {
      it('handles localhost with port in hostname (port stripped)', () => {
        // Note: hostname doesn't include port, but test the base case
        expect(isTrustedDomain('localhost')).toBe(true);
      });

      it('is case-sensitive (lowercase only)', () => {
        // Hostnames are typically lowercase, but verify behavior
        expect(isTrustedDomain('PODREAD.APP')).toBe(false);
        expect(isTrustedDomain('Podread.App')).toBe(false);
      });
    });
  });
});
