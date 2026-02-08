/**
 * Configuration for TTS browser extension
 * BASE_URL is injected at build time by esbuild
 *
 * Development: npm run build (uses localhost:3000)
 * Production:  NODE_ENV=production npm run build (uses podread.app)
 * Custom:      TTS_BASE_URL=https://custom.url npm run build
 */

declare const process: {
  env: {
    TTS_BASE_URL: string;
  };
};

export const BASE_URL = process.env.TTS_BASE_URL;
