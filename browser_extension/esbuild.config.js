const esbuild = require('esbuild');
const path = require('path');
const fs = require('fs');

const isWatch = process.argv.includes('--watch');

// Entry points for Chrome extension
// These files will be created by subsequent tasks
const entryPoints = [];

// Dynamically find entry points if they exist
const potentialEntries = ['background.ts', 'content.ts', 'popup.ts'];
for (const entry of potentialEntries) {
  const entryPath = path.join(__dirname, 'src', entry);
  if (fs.existsSync(entryPath)) {
    entryPoints.push(entryPath);
  }
}

// If no entry points exist yet, exit gracefully
if (entryPoints.length === 0) {
  console.log('No entry points found in src/. Skipping build.');
  console.log('Expected files: background.ts, content.ts, popup.ts');
  process.exit(0);
}

const buildOptions = {
  entryPoints,
  bundle: true,
  outdir: path.join(__dirname, 'dist'),
  platform: 'browser',
  target: 'es2020',
  format: 'iife',
  sourcemap: true,
  minify: process.env.NODE_ENV === 'production',
  logLevel: 'info',
};

async function build() {
  try {
    if (isWatch) {
      const ctx = await esbuild.context(buildOptions);
      await ctx.watch();
      console.log('Watching for changes...');
    } else {
      await esbuild.build(buildOptions);
      console.log('Build complete!');
    }
  } catch (error) {
    console.error('Build failed:', error);
    process.exit(1);
  }
}

build();
