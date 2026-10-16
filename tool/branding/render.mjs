// Renders the launcher icon SVGs in assets/branding/ to the PNGs that
// flutter_launcher_icons consumes, checks the adaptive safe zone, and builds
// a preview sheet. Usage: cd tool/branding && npm install && npm run render
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Resvg } from '@resvg/resvg-js';

const dir = join(dirname(fileURLToPath(import.meta.url)), '..', '..', 'assets', 'branding');
const BACKGROUND = '#0F2A52'; // keep in sync with flutter_launcher_icons.yaml

const svg = (name) => readFileSync(join(dir, name), 'utf8');
const render = (source, size) => new Resvg(source, { fitTo: { mode: 'width', value: size } }).render();
const dataUri = (png) => `data:image/png;base64,${Buffer.from(png).toString('base64')}`;

// 1. Exports at 1024 px.
const outputs = {
  'icon.svg': 'icon-1024.png',
  'icon-foreground.svg': 'icon-foreground-1024.png',
  'icon-monochrome.svg': 'icon-monochrome-1024.png',
};
for (const [src, out] of Object.entries(outputs)) {
  writeFileSync(join(dir, out), render(svg(src), 1024).asPng());
  console.log(`wrote assets/branding/${out}`);
}

// 2. Adaptive safe zone: launchers may crop anything outside the central
// 66dp of the 108dp canvas, i.e. a circle of radius 1024 * 33/108 ≈ 313 px.
for (const src of ['icon-foreground.svg', 'icon-monochrome.svg']) {
  const img = render(svg(src), 1024);
  const px = img.pixels;
  const r = (1024 * 33) / 108;
  let outside = 0;
  for (let y = 0; y < 1024; y++) {
    for (let x = 0; x < 1024; x++) {
      const alpha = px[(y * 1024 + x) * 4 + 3];
      if (alpha > 8 && Math.hypot(x + 0.5 - 512, y + 0.5 - 512) > r) outside++;
    }
  }
  if (outside > 0) {
    console.error(`FAIL ${src}: ${outside} visible pixels outside the adaptive safe zone`);
    process.exitCode = 1;
  } else {
    console.log(`ok   ${src}: inside the adaptive safe zone`);
  }
}

// 3. Preview sheet: legacy icon and adaptive icon (circle and squircle masks)
// at launcher sizes, on dark and light wallpapers. Sizes <= 48 are rendered at
// their real pixel size and enlarged, to show true small-size legibility.
const sizes = [192, 96, 48, 32];
const scaleUp = (s) => (s <= 48 ? 2 : 1);
function tile(kind, size, x, y) {
  const shown = size * scaleUp(size);
  const pixel = scaleUp(size) > 1 ? ' image-rendering="optimizeSpeed"' : '';
  if (kind === 'legacy') {
    return `<image x="${x}" y="${y}" width="${shown}" height="${shown}"${pixel} href="${dataUri(render(svg('icon.svg'), size).asPng())}"/>`;
  }
  // Adaptive: the visible shape is 72dp of the 108dp layers, so render the
  // layers 1.5x larger than the icon and clip.
  const layer = Math.round(size * 1.5);
  const fg = render(svg('icon-foreground.svg'), layer).asPng();
  const bg = `<svg xmlns="http://www.w3.org/2000/svg" width="${layer}" height="${layer}"><rect width="100%" height="100%" fill="${BACKGROUND}"/></svg>`;
  const flat = new Resvg(
    `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">
      <defs><clipPath id="m">${kind === 'circle'
        ? `<circle cx="${size / 2}" cy="${size / 2}" r="${size / 2}"/>`
        : `<rect width="${size}" height="${size}" rx="${size * 0.3}"/>`}</clipPath></defs>
      <g clip-path="url(#m)">
        <image x="${-size / 4}" y="${-size / 4}" width="${layer}" height="${layer}" href="${dataUri(new Resvg(bg).render().asPng())}"/>
        <image x="${-size / 4}" y="${-size / 4}" width="${layer}" height="${layer}" href="${dataUri(fg)}"/>
      </g></svg>`,
  ).render().asPng();
  return `<image x="${x}" y="${y}" width="${shown}" height="${shown}"${pixel} href="${dataUri(flat)}"/>`;
}

const rows = [
  ['dark', '#121212', '#E6E6E6'],
  ['light', '#F2F4F7', '#333333'],
];
const kinds = ['legacy', 'circle', 'squircle'];
const rowH = 230;
const colW = 640;
let body = '';
rows.forEach(([name, wall, ink], ri) => {
  kinds.forEach((kind, ki) => {
    const ox = 24 + ki * colW;
    const oy = 24 + ri * rowH;
    body += `<rect x="${ox - 12}" y="${oy - 12}" width="${colW - 24}" height="${rowH - 12}" rx="16" fill="${wall}"/>`;
    body += `<text x="${ox}" y="${oy + 206}" font-family="sans-serif" font-size="18" fill="${ink}">${kind} · ${name}</text>`;
    let x = ox;
    for (const s of sizes) {
      body += tile(kind, s, x, oy + (192 - s * scaleUp(s)) / 2);
      x += s * scaleUp(s) + 24;
    }
  });
});
const sheet = `<svg xmlns="http://www.w3.org/2000/svg" width="${24 + kinds.length * colW}" height="${24 + rows.length * rowH}">
  <rect width="100%" height="100%" fill="#FFFFFF"/>${body}</svg>`;
writeFileSync(join(dir, 'preview-sizes.png'), new Resvg(sheet, { font: { loadSystemFonts: true } }).render().asPng());
console.log('wrote assets/branding/preview-sizes.png');
