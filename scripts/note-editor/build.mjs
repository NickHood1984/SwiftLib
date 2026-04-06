import * as esbuild from 'esbuild'
import { readFileSync, writeFileSync, mkdirSync } from 'fs'
import { dirname, resolve } from 'path'
import { fileURLToPath } from 'url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const outDir = resolve(__dirname, '../../Sources/SwiftLib/Resources')

// Ensure output dir exists
mkdirSync(outDir, { recursive: true })

// Build JS + CSS into single bundles
const result = await esbuild.build({
  entryPoints: [resolve(__dirname, 'src/editor.js')],
  bundle: true,
  minify: true,
  format: 'iife',
  target: ['safari16'],
  write: false,
  loader: { '.css': 'css' },
  outdir: 'out',
})

let jsCode = ''
let cssCode = ''

for (const file of result.outputFiles) {
  if (file.path.endsWith('.js')) {
    jsCode = file.text
  } else if (file.path.endsWith('.css')) {
    cssCode = file.text
  }
}

// Generate single HTML file
const html = `<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
<style>${cssCode}</style>
</head>
<body>
<div id="editor"></div>
<script>${jsCode}</script>
</body>
</html>`

const outPath = resolve(outDir, 'NoteEditor.html')
writeFileSync(outPath, html, 'utf-8')

const sizeKB = (Buffer.byteLength(html, 'utf-8') / 1024).toFixed(1)
console.log(`✅ NoteEditor.html built → ${outPath} (${sizeKB} KB)`)
