import fs from "node:fs/promises";
import path from "node:path";
import { execFile } from "node:child_process";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);
const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), "..");
const vendorTranslationServer = path.join(root, "vendor", "translation-server");
const vendorTranslatorsCN = path.join(root, "vendor", "translators_CN");
const revisionsConfigPath = path.join(root, "config", "upstream-revisions.json");

async function gitRevision(dir) {
  try {
    const { stdout } = await execFileAsync("git", ["rev-parse", "HEAD"], { cwd: dir });
    return stdout.trim();
  } catch {
    return null;
  }
}

async function exists(dir) {
  try {
    await fs.access(dir);
    return true;
  } catch {
    return false;
  }
}

async function loadExistingConfig() {
  try {
    const raw = await fs.readFile(revisionsConfigPath, "utf8");
    return JSON.parse(raw);
  } catch {
    return {};
  }
}

async function main() {
  const translationServerPresent = await exists(vendorTranslationServer);
  const translatorsCNPresent = await exists(vendorTranslatorsCN);
  const existingConfig = await loadExistingConfig();
  const translationServerRevision = translationServerPresent ? await gitRevision(vendorTranslationServer) : null;
  const translatorsCNRevision = translatorsCNPresent ? await gitRevision(vendorTranslatorsCN) : null;

  const revisionsConfig = {
    translationServer: {
      repository: existingConfig.translationServer?.repository || "https://github.com/zotero/translation-server",
      revision: translationServerRevision || existingConfig.translationServer?.revision || null
    },
    translatorsCN: {
      repository: existingConfig.translatorsCN?.repository || "https://github.com/l0o0/translators_CN",
      revision: translatorsCNRevision || existingConfig.translatorsCN?.revision || null
    }
  };

  await fs.mkdir(path.dirname(revisionsConfigPath), { recursive: true });
  await fs.writeFile(revisionsConfigPath, `${JSON.stringify(revisionsConfig, null, 2)}\n`, "utf8");

  const result = {
    ok: true,
    translationServerPresent,
    translatorsCNPresent,
    translationServerRevision,
    translatorsCNRevision,
    configPath: revisionsConfigPath,
    message: "未执行上游拉取；当前脚本仅报告本地 vendor 状态并供后续 overlay 构建使用。"
  };

  process.stdout.write(JSON.stringify(result) + "\n");
}

main().catch((error) => {
  process.stderr.write(`${error.stack || error}\n`);
  process.exitCode = 1;
});
