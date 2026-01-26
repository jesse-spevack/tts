import { isTrustedDomain, TRUSTED_DOMAINS } from './content';

describe('content', () => {
  describe('TRUSTED_DOMAINS', () => {
    it('includes verynormal.dev', () => {
      expect(TRUSTED_DOMAINS).toContain('verynormal.dev');
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
      it('accepts verynormal.dev', () => {
        expect(isTrustedDomain('verynormal.dev')).toBe(true);
      });

      it('accepts localhost', () => {
        expect(isTrustedDomain('localhost')).toBe(true);
      });
    });

    describe('accepts subdomains of trusted domains', () => {
      it('accepts tts.verynormal.dev', () => {
        expect(isTrustedDomain('tts.verynormal.dev')).toBe(true);
      });

      it('accepts staging.tts.verynormal.dev', () => {
        expect(isTrustedDomain('staging.tts.verynormal.dev')).toBe(true);
      });

      it('accepts www.verynormal.dev', () => {
        expect(isTrustedDomain('www.verynormal.dev')).toBe(true);
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
        // notverynormal.dev should NOT be trusted (doesn't end with .verynormal.dev)
        expect(isTrustedDomain('notverynormal.dev')).toBe(false);
      });

      it('rejects domains with trusted domain in path-like position', () => {
        expect(isTrustedDomain('evil.com.verynormal.dev.attacker.com')).toBe(false);
      });

      it('rejects empty string', () => {
        expect(isTrustedDomain('')).toBe(false);
      });

      it('rejects domains that start with trusted domain', () => {
        // verynormal.dev.evil.com should NOT be trusted
        expect(isTrustedDomain('verynormal.dev.evil.com')).toBe(false);
      });
    });

    describe('edge cases', () => {
      it('handles localhost with port in hostname (port stripped)', () => {
        // Note: hostname doesn't include port, but test the base case
        expect(isTrustedDomain('localhost')).toBe(true);
      });

      it('is case-sensitive (lowercase only)', () => {
        // Hostnames are typically lowercase, but verify behavior
        expect(isTrustedDomain('VERYNORMAL.DEV')).toBe(false);
        expect(isTrustedDomain('Verynormal.Dev')).toBe(false);
      });
    });
  });
});
