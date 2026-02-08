const esbuild = require('esbuild');
const path = require('path');
const fs = require('fs');

const isWatch = process.argv.includes('--watch');
const distDir = path.join(__dirname, 'dist');

// Ensure dist directory exists
if (!fs.existsSync(distDir)) {
  fs.mkdirSync(distDir, { recursive: true });
}

// Copy static files to dist directory
function copyStaticFiles() {
  // Copy manifest.json
  const manifestSrc = path.join(__dirname, 'manifest.json');
  const manifestDest = path.join(distDir, 'manifest.json');
  if (fs.existsSync(manifestSrc)) {
    fs.copyFileSync(manifestSrc, manifestDest);
    console.log('Copied manifest.json to dist/');
  }

  // Copy icons directory
  const iconsSrc = path.join(__dirname, 'icons');
  const iconsDest = path.join(distDir, 'icons');
  if (fs.existsSync(iconsSrc)) {
    if (!fs.existsSync(iconsDest)) {
      fs.mkdirSync(iconsDest, { recursive: true });
    }
    const iconFiles = fs.readdirSync(iconsSrc);
    for (const file of iconFiles) {
      // Only copy PNG files, skip README
      if (file.endsWith('.png')) {
        fs.copyFileSync(path.join(iconsSrc, file), path.join(iconsDest, file));
        console.log(`Copied icons/${file} to dist/icons/`);
      }
    }
  }
}

// Entry points for Chrome extension
// These files will be created by subsequent tasks
const entryPoints = [];

// Dynamically find entry points if they exist
const potentialEntries = ['background.ts', 'content.ts'];
for (const entry of potentialEntries) {
  const entryPath = path.join(__dirname, 'src', entry);
  if (fs.existsSync(entryPath)) {
    entryPoints.push(entryPath);
  }
}

// Copy static files even if no TypeScript entry points exist
copyStaticFiles();

// If no entry points exist yet, exit gracefully
if (entryPoints.length === 0) {
  console.log('No TypeScript entry points found in src/. Skipping JS build.');
  console.log('Expected files: background.ts, content.ts');
  console.log('Static files have been copied to dist/');
  process.exit(0);
}

// Determine BASE_URL based on environment
const isProduction = process.env.NODE_ENV === 'production';
const baseUrl = process.env.TTS_BASE_URL || (isProduction ? 'https://podread.app' : 'http://localhost:3000');

const buildOptions = {
  entryPoints,
  bundle: true,
  outdir: path.join(__dirname, 'dist'),
  platform: 'browser',
  target: 'es2020',
  format: 'iife',
  sourcemap: true,
  minify: isProduction,
  logLevel: 'info',
  define: {
    'process.env.TTS_BASE_URL': JSON.stringify(baseUrl),
  },
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
