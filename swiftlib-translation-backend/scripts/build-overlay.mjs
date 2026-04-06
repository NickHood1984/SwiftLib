import fs from "node:fs/promises";
import path from "node:path";

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), "..");
const vendorTranslationServer = path.join(root, "vendor", "translation-server");
const vendorTranslatorsCN = path.join(root, "vendor", "translators_CN");
const outputDir = path.join(root, "runtime", "translators");

function translationServerTranslatorDirs() {
  return [
    path.join(vendorTranslationServer, "modules", "translators"),
    path.join(vendorTranslationServer, "translators")
  ];
}

async function ensureDir(dir) {
  await fs.mkdir(dir, { recursive: true });
}

async function copyTranslatorDir(sourceDir, destinationDir) {
  try {
    const entries = await fs.readdir(sourceDir, { withFileTypes: true });
    for (const entry of entries) {
      const src = path.join(sourceDir, entry.name);
      const dst = path.join(destinationDir, entry.name);
      if (entry.isDirectory()) {
        await ensureDir(dst);
        await copyTranslatorDir(src, dst);
      } else if (entry.isFile()) {
        await fs.copyFile(src, dst);
      }
    }
  } catch {
    // Ignore missing source directories in scaffold mode.
  }
}

async function main() {
  await ensureDir(outputDir);
  for (const dir of translationServerTranslatorDirs()) {
    await copyTranslatorDir(dir, outputDir);
  }
  await copyTranslatorDir(vendorTranslatorsCN, outputDir);
  process.stdout.write(JSON.stringify({ ok: true, outputDir }) + "\n");
}

main().catch((error) => {
  process.stderr.write(`${error.stack || error}\n`);
  process.exitCode = 1;
});
