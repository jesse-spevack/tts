# TTS Browser Extension

Chrome extension for sending articles to your TTS podcast feed.

## Setup

```bash
cd browser_extension
npm install
```

## Development

### Build

```bash
npm run build
```

### Watch mode (auto-rebuild on changes)

```bash
npm run watch
```

### Type checking

```bash
npm run typecheck
```

### Testing

```bash
npm test
npm run test:watch  # Watch mode
```

## Project Structure

```
browser_extension/
├── src/
│   ├── background.ts    # Service worker (to be added)
│   ├── content.ts       # Content script (to be added)
│   └── popup.ts         # Popup UI script (to be added)
├── dist/                # Build output (gitignored)
├── package.json
├── tsconfig.json
├── esbuild.config.js
└── jest.config.js
```

## Build Output

Built files are output to `dist/` folder. Load this folder as an unpacked extension in Chrome for development:

1. Open `chrome://extensions/`
2. Enable "Developer mode"
3. Click "Load unpacked"
4. Select the `dist/` folder
