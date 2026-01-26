/**
 * List of trusted domains that are allowed to provide tokens to the extension.
 * This prevents malicious sites from injecting tokens via the extension connect flow.
 *
 * Shared between content.ts and background.ts.
 */
export const TRUSTED_DOMAINS = ['verynormal.dev', 'localhost'];

/**
 * Check if a hostname is a trusted domain
 */
export function isTrustedDomain(hostname: string): boolean {
  return TRUSTED_DOMAINS.some(
    (domain) => hostname === domain || hostname.endsWith(`.${domain}`)
  );
}
