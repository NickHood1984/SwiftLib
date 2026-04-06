import http from "node:http";
import net from "node:net";
import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";
import { execFile, spawn } from "node:child_process";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";

const execFileAsync = promisify(execFile);
const token = crypto.randomUUID();
const version = "0.2.0";
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = process.env.SWIFTLIB_TRANSLATION_BACKEND_ROOT || __dirname;
const runtimeMode = process.env.SWIFTLIB_TRANSLATION_RUNTIME_MODE || "development";
const runtimeRootDir = process.env.SWIFTLIB_TRANSLATION_RUNTIME_ROOT || rootDir;
const seedRootDir = process.env.SWIFTLIB_TRANSLATION_SEED_ROOT || rootDir;
const defaultTranslationServerURL = "http://127.0.0.1:1969";
let translationServerBaseURL = process.env.TRANSLATION_SERVER_URL || defaultTranslationServerURL;
const pendingSessions = new Map();
const PENDING_SESSION_TTL_MS = 30 * 60 * 1000; // 30 minutes
const MAX_PENDING_SESSIONS = 100;
const MAX_REQUEST_BODY_BYTES = 1 * 1024 * 1024; // 1 MB
setInterval(() => {
  const now = Date.now();
  for (const [id, session] of pendingSessions) {
    if (now - session.createdAt > PENDING_SESSION_TTL_MS) {
      pendingSessions.delete(id);
    }
  }
}, 60000);
let embeddedTranslationServer = null;
let embeddedTranslationServerStarting = null;
let translationServerDown = false;
let translationServerRevision = normalizeOptional(process.env.TRANSLATION_SERVER_REVISION);
let translatorsCNRevision = normalizeOptional(process.env.TRANSLATORS_CN_REVISION);
let overlayRevision = normalizeOptional(process.env.SWIFTLIB_TRANSLATION_OVERLAY_REVISION);
let licensesVersion = normalizeOptional(process.env.SWIFTLIB_TRANSLATION_LICENSES_VERSION);
let backendPackageVersion = normalizeOptional(process.env.SWIFTLIB_TRANSLATION_BACKEND_VERSION);

function normalizeOptional(value) {
  if (value == null) return null;
  const trimmed = String(value).trim();
  return trimmed.length ? trimmed : null;
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function runtimeTranslatorsDir() {
  return path.join(runtimeRootDir, "runtime", "translators");
}

function seedTranslatorsDir() {
  return path.join(seedRootDir, "runtime", "translators");
}

function runtimeStatePath() {
  return path.join(runtimeRootDir, "runtime-state.json");
}

async function exists(targetPath) {
  try {
    await fs.access(targetPath);
    return true;
  } catch {
    return false;
  }
}

async function gitRevision(cwd) {
  try {
    const { stdout } = await execFileAsync("git", ["rev-parse", "HEAD"], { cwd });
    return stdout.trim() || null;
  } catch {
    return null;
  }
}

async function waitForPort(port, host = "127.0.0.1", timeoutMs = 30000) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    try {
      await new Promise((resolve, reject) => {
        const socket = net.connect({ port, host });
        socket.once("connect", () => {
          socket.destroy();
          resolve(true);
        });
        socket.once("error", reject);
      });
      return true;
    } catch {
      // Keep polling until timeout.
    }
    await delay(250);
  }
  return false;
}

async function readJSON(filePath) {
  try {
    const raw = await fs.readFile(filePath, "utf8");
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

async function loadPackageMetadata() {
  if (backendPackageVersion && licensesVersion) {
    return;
  }

  const packageJSON = await readJSON(path.join(rootDir, "package.json"));
  if (!backendPackageVersion) {
    backendPackageVersion = normalizeOptional(packageJSON?.version);
  }
  if (!licensesVersion && backendPackageVersion) {
    licensesVersion = `${backendPackageVersion}-${process.versions.node}`;
  }
}

async function writeJSON(filePath, payload) {
  await fs.mkdir(path.dirname(filePath), { recursive: true });
  await fs.writeFile(filePath, `${JSON.stringify(payload, null, 2)}\n`, "utf8");
}

async function copyDir(sourceDir, destinationDir) {
  const entries = await fs.readdir(sourceDir, { withFileTypes: true });
  await fs.mkdir(destinationDir, { recursive: true });
  for (const entry of entries) {
    const src = path.join(sourceDir, entry.name);
    const dst = path.join(destinationDir, entry.name);
    if (entry.isDirectory()) {
      await copyDir(src, dst);
    } else if (entry.isFile()) {
      await fs.copyFile(src, dst);
    }
  }
}

async function ensureLocalRevisions() {
  const configured = await readJSON(path.join(rootDir, "config", "upstream-revisions.json"));
  if (!translationServerRevision) {
    translationServerRevision = normalizeOptional(configured?.translationServer?.revision);
  }
  if (!translatorsCNRevision) {
    translatorsCNRevision = normalizeOptional(configured?.translatorsCN?.revision);
  }
  if (!translationServerRevision) {
    translationServerRevision = await gitRevision(path.join(rootDir, "vendor", "translation-server"));
  }
  if (!translatorsCNRevision) {
    translatorsCNRevision = await gitRevision(path.join(rootDir, "vendor", "translators_CN"));
  }
  if (!overlayRevision) {
    overlayRevision = [translationServerRevision, translatorsCNRevision]
      .filter(Boolean)
      .join("+") || null;
  }
  await loadPackageMetadata();
}

async function ensureRuntimeOverlay({ force = false, reason = "startup" } = {}) {
  const sourceDir = seedTranslatorsDir();
  const targetDir = runtimeTranslatorsDir();
  const targetStatePath = runtimeStatePath();

  if (!(await exists(sourceDir))) {
    await fs.mkdir(path.dirname(targetDir), { recursive: true });
    const existingState = await readJSON(targetStatePath);
    return {
      ok: true,
      copied: false,
      message: "未找到内置 translators seed，沿用现有运行时目录。",
      state: existingState,
      runtimeRoot: runtimeRootDir
    };
  }

  // 当 seed 目录与运行时目录相同时（开发模式默认），跳过复制
  const resolvedSource = path.resolve(sourceDir);
  const resolvedTarget = path.resolve(targetDir);
  const sameDir = resolvedSource === resolvedTarget;

  const currentState = (await readJSON(targetStatePath)) || {};
  const targetExists = await exists(targetDir);
  const needsCopy = !sameDir && (force
    || !targetExists
    || currentState.overlayRevision !== overlayRevision
    || currentState.translationServerRevision !== translationServerRevision
    || currentState.translatorsCNRevision !== translatorsCNRevision);

  if (needsCopy) {
    await fs.rm(targetDir, { recursive: true, force: true });
    await copyDir(sourceDir, targetDir);
  }

  const updatedAt = new Date().toISOString();
  const nextState = {
    overlayRevision,
    translationServerRevision,
    translatorsCNRevision,
    updatedAt,
    message: force
      ? "已同步当前 App 内置 translators 到本地运行时。"
      : (needsCopy ? "已完成首启/升级时的 translators 同步。" : currentState.message || "运行时 translators 已是最新。"),
    reason
  };
  await writeJSON(targetStatePath, nextState);

  return {
    ok: true,
    copied: needsCopy,
    message: nextState.message,
    state: nextState,
    runtimeRoot: runtimeRootDir
  };
}

async function ensureEmbeddedTranslationServer() {
  if (process.env.TRANSLATION_SERVER_URL) {
    await ensureLocalRevisions();
    await ensureRuntimeOverlay({ force: false, reason: "external" });
    return;
  }

  if (embeddedTranslationServerStarting) {
    await embeddedTranslationServerStarting;
    return;
  }

  embeddedTranslationServerStarting = (async () => {
    await ensureLocalRevisions();
    await ensureRuntimeOverlay({ force: false, reason: "startup" });

    if (await waitForPort(1969, "127.0.0.1", 500)) {
      translationServerBaseURL = defaultTranslationServerURL;
      return;
    }

    const translationServerRoot = path.join(rootDir, "vendor", "translation-server");
    const translatorsDir = runtimeTranslatorsDir();
    const serverEntry = path.join(translationServerRoot, "src", "server.js");
    const nodeModulesDir = path.join(translationServerRoot, "node_modules");

    if (!(await exists(serverEntry)) || !(await exists(nodeModulesDir)) || !(await exists(translatorsDir))) {
      translationServerBaseURL = defaultTranslationServerURL;
      return;
    }

    embeddedTranslationServer = spawn(process.execPath, ["src/server.js"], {
      cwd: translationServerRoot,
      env: {
        ...process.env,
        TRANSLATORS_DIR: translatorsDir,
        HOST: "127.0.0.1",
        PORT: String(new URL(defaultTranslationServerURL).port || 1969)
      },
      stdio: ["ignore", "pipe", "pipe"]
    });

    embeddedTranslationServer.stdout?.on("data", (chunk) => process.stderr.write(`[translation-server] ${chunk}`));
    embeddedTranslationServer.stderr?.on("data", (chunk) => process.stderr.write(`[translation-server] ${chunk}`));
    embeddedTranslationServer.on("exit", (code) => {
      embeddedTranslationServer = null;
      if (code !== 0 && code !== null) {
        translationServerDown = true;
        process.stderr.write(`[translation-server] 进程异常退出 code=${code}，后续请求将跳过\n`);
      }
    });

    const ready = await waitForPort(1969, "127.0.0.1", 30000);
    if (!ready) {
      throw new Error("本地 translation-server 启动超时。");
    }
    translationServerBaseURL = defaultTranslationServerURL;
  })();

  try {
    await embeddedTranslationServerStarting;
  } finally {
    embeddedTranslationServerStarting = null;
  }
}

function json(response, statusCode, payload) {
  response.writeHead(statusCode, { "Content-Type": "application/json; charset=utf-8" });
  response.end(JSON.stringify(payload));
}

function normalizeSource(url) {
  try {
    const host = new URL(url).host.toLowerCase();
    if (host.includes("cnki")) return "cnki";
    if (host.includes("wanfang")) return "wanfang";
    if (host.includes("cqvip") || host.includes("vip")) return "vip";
    if (host.includes("douban")) return "douban";
    if (host.includes("duxiu")) return "duxiu";
    if (host.includes("nlc.cn") || host.includes("wenjin")) return "wenjin";
  } catch {
    // Ignore malformed URLs.
  }
  return "translationServer";
}

function normalizeItem(item) {
  if (!item || typeof item !== "object") return null;
  return item;
}

function normalizeCandidate(candidateId, candidate, sessionId, detailURL) {
  return {
    id: candidateId,
    title: candidate?.title || candidateId,
    creators: (candidate?.creators || []).map((creator) => {
      if (creator?.name) return creator.name;
      return [creator?.lastName, creator?.firstName].filter(Boolean).join(" ").trim();
    }).filter(Boolean),
    year: extractYear(candidate?.date),
    source: normalizeSource(detailURL),
    referenceType: null,
    publisher: candidate?.publisher || null,
    containerTitle: candidate?.publicationTitle || candidate?.bookTitle || candidate?.proceedingsTitle || null,
    detailURL: detailURL || candidate?.url || null,
    matchedBy: ["translator"],
    workKind: "unknown",
    sessionID: sessionId
  };
}

function extractYear(value) {
  if (!value) return null;
  const match = String(value).match(/\b(19\d{2}|20\d{2})\b/);
  return match ? Number(match[1]) : null;
}

async function callTranslationServer(endpoint, options) {
  if (translationServerDown) {
    throw new Error("translation-server 已崩溃，请重启应用。");
  }

  let lastError = null;
  const maxAttempts = 6;
  const baseDelay = 350;

  for (let attempt = 0; attempt < maxAttempts; attempt += 1) {
    try {
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), 15000);
      const mergedOptions = {
        ...options,
        signal: controller.signal
      };
      const response = await fetch(`${translationServerBaseURL}${endpoint}`, mergedOptions);
      clearTimeout(timeoutId);
      const text = await response.text();
      let parsed = null;
      try {
        parsed = text ? JSON.parse(text) : null;
      } catch {
        parsed = null;
      }
      return { response, text, parsed };
    } catch (error) {
      lastError = error;
      const backoffMs = baseDelay * Math.pow(2, attempt);  // 350, 700, 1400, 2800, 5600, 11200
      await delay(Math.min(backoffMs, 10000));
    }
  }

  throw lastError || new Error("translation-server 请求失败。");
}

async function handleResolve(body, response) {
  const endpoint = body?.inputType === "url" ? "/web" : "/search";
  const payload = String(body?.value || "").trim();
  if (!payload) {
    json(response, 400, { message: "缺少输入值。" });
    return;
  }

  const { response: upstream, text, parsed } = await callTranslationServer(endpoint, {
    method: "POST",
    headers: { "Content-Type": "text/plain; charset=utf-8" },
    body: payload
  });

  if (upstream.status === 200) {
    const item = Array.isArray(parsed) ? parsed[0] : parsed;
    if (!item) {
      json(response, 404, { message: "未找到可用元数据。" });
      return;
    }
    json(response, 200, { item: normalizeItem(item) });
    return;
  }

  if (upstream.status === 300 && parsed?.items) {
    if (pendingSessions.size >= MAX_PENDING_SESSIONS) {
      // Evict oldest session to make room
      const oldest = pendingSessions.keys().next().value;
      if (oldest) pendingSessions.delete(oldest);
    }
    const sessionId = crypto.randomUUID();
    pendingSessions.set(sessionId, { endpoint, payload: parsed, createdAt: Date.now() });
    const candidates = Object.entries(parsed.items).map(([id, item]) =>
      normalizeCandidate(id, item, sessionId, parsed.url)
    );
    json(response, 300, { candidates });
    return;
  }

  json(response, upstream.status, { message: parsed?.message || text || "translation-server 请求失败。" });
}

async function handleResolveSelection(body, response) {
  const sessionId = String(body?.sessionId || "");
  const selectedIds = Array.isArray(body?.selectedIds) ? body.selectedIds.map(String) : [];
  const session = pendingSessions.get(sessionId);
  if (!session) {
    json(response, 404, { message: "候选会话不存在或已过期。" });
    return;
  }
  if (!selectedIds.length) {
    json(response, 400, { message: "必须至少选择一个候选。" });
    return;
  }

  const payload = {
    ...session.payload,
    items: Object.fromEntries(
      Object.entries(session.payload.items || {}).filter(([id]) => selectedIds.includes(id))
    )
  };

  const { response: upstream, text, parsed } = await callTranslationServer(session.endpoint, {
    method: "POST",
    headers: { "Content-Type": "application/json; charset=utf-8" },
    body: JSON.stringify(payload)
  });

  if (upstream.status === 200) {
    const item = Array.isArray(parsed) ? parsed[0] : parsed;
    if (!item) {
      json(response, 404, { message: "选择后的候选没有返回条目。" });
      return;
    }
    pendingSessions.delete(sessionId);
    json(response, 200, { item: normalizeItem(item) });
    return;
  }

  json(response, upstream.status, { message: parsed?.message || text || "候选解析失败。" });
}

// ─────────────────────────────────────────────────────────────────────────────
// 百度学术适配器（Baidu Scholar Adapter）
// 直接抓取 xueshu.baidu.com 的搜索结果和详情页，无需 translation-server
// ─────────────────────────────────────────────────────────────────────────────

const BAIDU_SCHOLAR_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36";
const BAIDU_SCHOLAR_SEARCH_URL = "https://xueshu.baidu.com/s";
const BAIDU_SCHOLAR_DETAIL_URL = "https://xueshu.baidu.com/ndscholar/browse/detail";

/**
 * 从百度学术搜索结果 HTML 中解析文献列表
 * 搜索结果结构：
 *   .paper-wrap  → 每条结果
 *     h3 a span  → 标题
 *     h3 a[href] → 详情页 URL（含 paperid）
 *     .paper-info a → 作者（多个 <a>）
 *     .paper-info span（非链接）→ 期刊/机构
 *     .paper-abstract → 摘要片段
 */
function parseBaiduSearchResults(html) {
  const results = [];

  // 提取每个 paper-wrap 块
  const paperWrapRegex = /<div[^>]+class="[^"]*paper-wrap[^"]*"[^>]*>(.*?)<\/div>\s*(?=<div[^>]+class="[^"]*paper-wrap|$)/gs;
  let wrapMatch;

  // 更可靠的方式：按 h3 分割，每个 h3 对应一篇文献
  // 百度学术搜索结果页面结构：每篇文献以 <h3 class="t"> 开头
  const blocks = html.split(/<h3[^>]*class="[^"]*\bt\b[^"]*"/);

  for (let i = 1; i < blocks.length; i++) {
    const block = blocks[i];
    const result = {};

    // 标题：<a href="...">...<span>标题文字</span>...</a>
    const titleMatch = block.match(/<a[^>]+href="([^"]+)"[^>]*>\s*(?:<[^>]+>\s*)*([^<]{2,}?)\s*(?:<\/[^>]+>\s*)*<\/a>/);
    if (titleMatch) {
      result.title = titleMatch[2].replace(/\s+/g, " ").trim();
      result.detailURL = titleMatch[1].startsWith("http") ? titleMatch[1] : `https://xueshu.baidu.com${titleMatch[1]}`;
      // 从 URL 提取 paperid
      const paperIdMatch = result.detailURL.match(/paperid=([a-f0-9]+)/);
      if (paperIdMatch) result.paperId = paperIdMatch[1];
    }

    // 作者：paper-info 中的 <a> 链接（包含 author 关键字）
    const authorSection = block.match(/<p[^>]*class="[^"]*paper-info[^"]*"[^>]*>(.*?)<\/p>/s);
    if (authorSection) {
      const authorMatches = [...authorSection[1].matchAll(/<a[^>]+href="[^"]*(?:author|wd=)[^"]*"[^>]*>([^<]+)<\/a>/g)];
      result.authors = authorMatches.map(m => m[1].replace(/[，,\s]+$/, "").trim()).filter(a => a.length > 0 && a.length < 20);

      // 期刊/来源：非链接的 <span> 文本，通常包含《》
      const journalMatch = authorSection[1].match(/<span[^>]*>([^<]*《[^》]+》[^<]*)<\/span>/);
      if (journalMatch) {
        result.journal = journalMatch[1].replace(/^[-\s]+/, "").trim();
      }

      // 年份：4位数字
      const yearMatch = authorSection[1].match(/(?:^|[^\d])((?:19|20)\d{2})(?:[^\d]|$)/);
      if (yearMatch) result.year = parseInt(yearMatch[1], 10);
    }

    // 摘要片段
    const abstractMatch = block.match(/<p[^>]*class="[^"]*abstract[^"]*"[^>]*>([^<]+)/);
    if (abstractMatch) result.abstract = abstractMatch[1].trim();

    if (result.title && result.title.length > 1) {
      results.push(result);
    }
  }

  return results;
}

/**
 * 从百度学术详情页 HTML 中提取完整元数据
 * 详情页结构：
 *   .title-wrap .title span  → 标题
 *   .tips .source            → 期刊/机构
 *   .item .label + .detail   → 各字段（作者、摘要、关键词、DOI、被引量等）
 *     .detail-author .detail-link span → 作者名
 */
function parseBaiduDetailPage(html) {
  const meta = {};

  // 标题：.title-wrap 内的 <span>
  const titleMatch = html.match(/class="title"[^>]*>\s*<span[^>]*>([^<]+)<\/span>/);
  if (titleMatch) meta.title = titleMatch[1].trim();

  // 机构/期刊来源：.tips .source
  const sourceMatch = html.match(/class="source"[^>]*>([^<]+)<\/a>/);
  if (sourceMatch) meta.source = sourceMatch[1].trim();

  // 解析 .item 结构：每个 item 包含 label + detail
  const itemRegex = /class="item"[^>]*>.*?class="label"[^>]*>([^<]+)<\/div>.*?class="[^"]*detail[^"]*"[^>]*>(.*?)<\/div>\s*<\/div>/gs;
  let itemMatch;
  while ((itemMatch = itemRegex.exec(html)) !== null) {
    const label = itemMatch[1].trim().replace(/[：:]/g, "");
    const detailHTML = itemMatch[2];
    const detailText = detailHTML.replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim();

    switch (label) {
      case "作者":
        // 提取所有作者链接
        const authorMatches = [...detailHTML.matchAll(/<span[^>]*>([^<]+)<\/span>/g)];
        meta.authors = authorMatches.map(m => m[1].trim()).filter(a => a.length > 0 && a.length < 20);
        if (!meta.authors.length) meta.authors = detailText.split(/[,，、]/).map(a => a.trim()).filter(Boolean);
        break;
      case "摘要":
        meta.abstract = detailText;
        break;
      case "关键词":
        meta.keywords = detailText.split(/[;；]/).map(k => k.trim()).filter(Boolean);
        break;
      case "DOI":
        meta.doi = detailText;
        break;
      case "被引量":
        meta.citationCount = parseInt(detailText, 10) || 0;
        break;
      case "学位级别":
        meta.degree = detailText;
        break;
      case "发表时间":
      case "出版时间":
        const yearMatch = detailText.match(/((?:19|20)\d{2})/);
        if (yearMatch) meta.year = parseInt(yearMatch[1], 10);
        break;
    }
  }

  // 年份：从 source 或页面文本提取
  if (!meta.year) {
    const yearMatch = html.match(/(?:发表|出版|年份)[^\d]*((?:19|20)\d{2})/);
    if (yearMatch) meta.year = parseInt(yearMatch[1], 10);
  }

  return meta;
}

/**
 * 计算标题相似度（简单字符重叠率，用于筛选最佳候选）
 */
function titleSimilarity(a, b) {
  if (!a || !b) return 0;
  const normalize = s => s.replace(/[\s《》「」【】\(\)（）:：\-—]+/g, "").toLowerCase();
  const na = normalize(a);
  const nb = normalize(b);
  if (na === nb) return 1.0;
  // 计算最长公共子序列长度近似（用字符集重叠）
  const setA = new Set(na);
  const setB = new Set(nb);
  let common = 0;
  for (const c of setA) { if (setB.has(c)) common++; }
  return (2 * common) / (setA.size + setB.size);
}

/**
 * 百度学术搜索：返回搜索结果列表
 */
async function searchBaiduScholar(query, debugLog) {
  const searchURL = `${BAIDU_SCHOLAR_SEARCH_URL}?wd=${encodeURIComponent(query)}&ie=utf-8&tn=SE_baiduxueshu_c1gjeupa&sc_hit=1`;
  debugLog.push(`[BaiduScholar] 搜索 URL: ${searchURL}`);

  const resp = await fetch(searchURL, {
    headers: {
      "User-Agent": BAIDU_SCHOLAR_UA,
      "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      "Accept-Language": "zh-CN,zh;q=0.9",
      "Referer": "https://xueshu.baidu.com/"
    },
    redirect: "follow",
    signal: AbortSignal.timeout(12000)
  });

  if (!resp.ok) {
    debugLog.push(`[BaiduScholar] 搜索请求失败: HTTP ${resp.status}`);
    return [];
  }

  const html = await resp.text();
  debugLog.push(`[BaiduScholar] 搜索响应 HTML 长度: ${html.length} 字符`);

  // 检测百度反爬/验证码页面
  if (html.length < 1000 || html.includes("验证码") || html.includes("captcha") || html.includes("安全验证") || html.includes("百度安全验证")) {
    debugLog.push(`[BaiduScholar] 检测到反爬/验证码页面，跳过`);
    return [];
  }

  const results = parseBaiduSearchResults(html);
  debugLog.push(`[BaiduScholar] 解析到 ${results.length} 条搜索结果`);
  results.forEach((r, i) => {
    debugLog.push(`[BaiduScholar]   [${i}] 标题: ${r.title || "(无)"} | 作者: ${(r.authors || []).join(",") || "(无)"} | 年份: ${r.year || "(无)"} | paperid: ${r.paperId || "(无)"}`);
  });

  return results;
}

/**
 * 百度学术详情页抓取：通过 paperid 获取完整元数据
 */
async function fetchBaiduDetail(paperId, debugLog) {
  const detailURL = `${BAIDU_SCHOLAR_DETAIL_URL}?paperid=${paperId}&site=xueshu_se`;
  debugLog.push(`[BaiduScholar] 抓取详情页: ${detailURL}`);

  const resp = await fetch(detailURL, {
    headers: {
      "User-Agent": BAIDU_SCHOLAR_UA,
      "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      "Accept-Language": "zh-CN,zh;q=0.9",
      "Referer": BAIDU_SCHOLAR_SEARCH_URL
    },
    redirect: "follow",
    signal: AbortSignal.timeout(12000)
  });

  if (!resp.ok) {
    debugLog.push(`[BaiduScholar] 详情页请求失败: HTTP ${resp.status}`);
    return null;
  }

  const html = await resp.text();
  debugLog.push(`[BaiduScholar] 详情页 HTML 长度: ${html.length} 字符`);

  const meta = parseBaiduDetailPage(html);
  debugLog.push(`[BaiduScholar] 详情页解析结果: 标题=${meta.title || "(无)"} | 作者=${(meta.authors || []).join(",") || "(无)"} | DOI=${meta.doi || "(无)"} | 关键词=${(meta.keywords || []).join(";") || "(无)"}`);

  return meta;
}

/**
 * 将百度学术元数据转换为 SwiftLib 标准格式
 */
function baiduMetaToSwiftLibItem(searchResult, detailMeta) {
  const meta = { ...searchResult, ...detailMeta };

  // 合并作者（详情页优先，因为更完整）
  const authors = (detailMeta?.authors?.length ? detailMeta.authors : searchResult?.authors || []);

  return {
    itemType: meta.degree ? "thesis" : "journalArticle",
    title: meta.title || "",
    creators: authors.map(name => ({ creatorType: "author", name })),
    date: meta.year ? String(meta.year) : null,
    publicationTitle: meta.journal || meta.source || null,
    abstractNote: meta.abstract || null,
    DOI: meta.doi || null,
    tags: (meta.keywords || []).map(k => ({ tag: k })),
    extra: [
      meta.degree ? `学位级别: ${meta.degree}` : null,
      meta.citationCount != null ? `被引量: ${meta.citationCount}` : null,
      meta.paperId ? `百度学术ID: ${meta.paperId}` : null
    ].filter(Boolean).join("\n") || null,
    url: searchResult?.detailURL || null,
    _source: "baiduScholar"
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// 知网 Export API（更接近原生实现）
// 原理：先用 kns8s/brief/grid 搜索拿到结果，再调用 dm8/API/GetExport 导出 RefWorks / EndNote 文本。
// 当前社区方案普遍依赖有效登录态或浏览器 cookie，匿名请求稳定性较差。
// ─────────────────────────────────────────────────────────────────────────────

const CNKI_EXPORT_URL = "https://kns.cnki.net/dm8/API/GetExport";
const CNKI_SEARCH_URL = "https://kns.cnki.net/kns8s/brief/grid";
const CNKI_HOME_URL = "https://kns.cnki.net/kns8s/defaultresult/index";
const CNKI_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15";

function normalizeCNKIText(value) {
  return String(value || "").replace(/\s+/g, " ").trim();
}

function normalizeCookieHeader(value) {
  const normalized = normalizeCNKIText(value);
  return normalized || null;
}

function sanitizeExportText(raw) {
  let text = String(raw || "")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/p>/gi, "\n")
    .replace(/<[^>]+>/g, "");

  const htmlEntities = new Map([
    ["&nbsp;", " "],
    ["&amp;", "&"],
    ["&lt;", "<"],
    ["&gt;", ">"],
    ["&quot;", "\""],
    ["&#39;", "'"]
  ]);

  for (const [entity, replacement] of htmlEntities) {
    text = text.split(entity).join(replacement);
  }

  return text
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n")
    .trim();
}

function exportTextFromPayload(text) {
  try {
    const json = JSON.parse(text);
    if (json?.code === 1 && Array.isArray(json?.data)) {
      for (const item of json.data) {
        const key = String(item?.key || "").toLowerCase();
        if (key === "endnote" || key === "refworks" || key === "ris") {
          if (Array.isArray(item?.value) && item.value.length > 0) {
            return sanitizeExportText(item.value[0]);
          }
          if (typeof item?.value === "string") {
            return sanitizeExportText(item.value);
          }
        }
      }
    }
  } catch {
    // Not JSON; fall back to plain text parsing below.
  }

  const sanitized = sanitizeExportText(text);
  return sanitized.length ? sanitized : null;
}

function cnkiSearchExpression({ title, author, doi, fileName }) {
  const clauses = [];
  if (normalizeCNKIText(doi)) {
    clauses.push(`DOI='${normalizeCNKIText(doi)}'`);
  }
  if (normalizeCNKIText(title)) {
    clauses.push(`TI %= '${normalizeCNKIText(title)}'`);
  }

  let expression = clauses.join(" OR ");
  if (!expression) {
    expression = `TI %= '${normalizeCNKIText(fileName)}'`;
  }
  if (normalizeCNKIText(author)) {
    expression = `(${expression}) AND AU='${normalizeCNKIText(author)}'`;
  }
  return expression;
}

function urlEncodedFormBody(fields) {
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(fields)) {
    if (value == null) continue;
    if (typeof value === "object") {
      params.set(key, JSON.stringify(value));
    } else {
      params.set(key, String(value));
    }
  }
  return params.toString();
}

function cnkiSearchKeyword({ title, doi, fileName }) {
  return normalizeCNKIText(title) || normalizeCNKIText(doi) || normalizeCNKIText(fileName);
}

function cnkiSearchReferer({ title, doi, fileName }) {
  const keyword = cnkiSearchKeyword({ title, doi, fileName });
  return `${CNKI_HOME_URL}?crossids=YSTT4HG0%2CLSTPFY1C%2CJUP3MUPD%2CMPMFIG1A%2CWQ0UVIAA%2CBLZOG7CK%2CPWFIRAGL%2CEMRPGLPA%2CNLBO1Z6R%2CNN3FJMUV&korder=SU&kw=${encodeURIComponent(keyword)}`;
}

function buildCNKISearchBody({ title, author, doi, fileName }) {
  const expression = cnkiSearchExpression({ title, author, doi, fileName });
  const aside = expression.replace(/'/g, "&#39;");
  const queryJSON = {
    Platform: "",
    Resource: "CROSSDB",
    Classid: "WD0FTY92",
    Products: "",
    QNode: {
      QGroup: [
        [
          {
            Key: "Subject",
            Title: "",
            Logic: 0,
            Items: [
              {
                Key: "Expert",
                Title: "",
                Logic: 0,
                Field: "EXPERT",
                Operator: 0,
                Value: expression,
                Value2: ""
              }
            ],
            ChildItems: []
          },
          {
            Key: "ControlGroup",
            Title: "",
            Logic: 0,
            Items: [],
            ChildItems: []
          }
        ]
      ]
    },
    ExScope: "1",
    SearchType: 4,
    Rlang: "CHINESE",
    KuaKuCode: "YSTT4HG0,LSTPFY1C,JUP3MUPD,MPMFIG1A,WQ0UVIAA,BLZOG7CK,PWFIRAGL,EMRPGLPA,NLBO1Z6R,NN3FJMUV",
    SearchFrom: 1
  };

  return urlEncodedFormBody({
    boolSearch: "true",
    QueryJson: queryJSON,
    pageNum: "1",
    pageSize: "20",
    sortField: "",
    sortType: "",
    dstyle: "listmode",
    productStr: "YSTT4HG0,LSTPFY1C,RMJLXHZ3,JQIRZIYA,JUP3MUPD,1UR4K4HZ,BPBAFJ5S,R79MZMCB,MPMFIG1A,WQ0UVIAA,NB3BWEHK,XVLO76FD,HR1YT1Z9,BLZOG7CK,PWFIRAGL,EMRPGLPA,J708GVCE,ML4DRIDX,NLBO1Z6R,NN3FJMUV,",
    aside: `(${aside})`,
    searchFrom: "资源范围：总库;++中英文扩展;++时间范围：更新时间：不限;++",
    CurPage: "1"
  });
}

/**
 * 解析知网 RefWorks 格式文本，提取结构化元数据
 * 格式示例：
 *   T1 蓝田生物群：一个认识多细胞生物起源和早期演化的新窗口
 *   A1 袁训来;陈哲;肖书海
 *   JF 科学通报
 *   YR 2012
 *   VL 57
 *   IS 34
 *   SP 3219
 *   EP 3227
 *   DO 10.1360/972012-1168
 *   AB 摘要内容...
 *   KW 关键词1;关键词2
 */
function parseRefWorks(text) {
  if (!text || typeof text !== "string") return null;
  const lines = text.split(/\r?\n/);
  const item = {};
  let currentKey = null;
  let currentValue = [];

  const flush = () => {
    if (currentKey) {
      item[currentKey] = currentValue.join(" ").trim();
    }
  };

  for (const line of lines) {
    const match = /^([A-Z][A-Z0-9])\s+(.*)/.exec(line);
    if (match) {
      flush();
      currentKey = match[1];
      currentValue = [match[2].trim()];
    } else if (currentKey && line.startsWith("  ")) {
      currentValue.push(line.trim());
    }
  }
  flush();

  if (!item.T1) return null;

  // 解析作者（分号分隔）
  const authors = (item.A1 || item.AU || "")
    .split(/[;；]/).map(s => s.trim()).filter(Boolean);

  // 解析关键词
  const keywords = (item.KW || "")
    .split(/[;；]/).map(s => s.trim()).filter(Boolean);

  // 确定文献类型
  let itemType = "journalArticle";
  if (item.TY) {
    const ty = item.TY.toUpperCase();
    if (ty === "THES" || ty === "DISS") itemType = "thesis";
    else if (ty === "CONF") itemType = "conferencePaper";
    else if (ty === "BOOK") itemType = "book";
    else if (ty === "RPRT") itemType = "report";
  }

  return {
    itemType,
    title: item.T1 || "",
    creators: authors.map(name => ({ creatorType: "author", name })),
    date: item.YR || item.PY || null,
    publicationTitle: item.JF || item.JO || item.BT || null,
    volume: item.VL || null,
    issue: item.IS || null,
    pages: item.SP && item.EP ? `${item.SP}-${item.EP}` : (item.SP || item.EP || item.PP || null),
    DOI: item.DO || item.DI || null,
    ISSN: item.SN || null,
    abstractNote: item.AB || item.N2 || null,
    tags: keywords.map(k => ({ tag: k })),
    publisher: item.PB || null,
    place: item.PP || null,
    university: item.PB || null,
    language: "zh-CN",
    _source: "cnki-showexport"
  };
}

/**
 * 从知网搜索结果 HTML 中提取 filename 和 dbname
 * 知网搜索结果中，每条文献的链接格式为：
 *   /kcms2/article/abstract?v=...&dbcode=CJFD&dbname=CJFD2024&filename=KXTB202401001
 * 或通过隐藏 input 标签：
 *   <input type="hidden" id="paramfilename" value="KXTB202401001">
 *   <input type="hidden" id="paramdbname" value="CJFD2024">
 *   <input type="hidden" id="paramdbcode" value="CJFD">
 */
function extractCNKIParams(html) {
  const results = [];

  // 方法1：从文章链接中提取 dbname 和 filename
  const linkRegex = /href=["']([^"']*(?:kcms2\/article\/abstract|KCMS\/detail\/detail\.aspx)[^"']*dbname=([A-Z0-9]+)[^"']*filename=([A-Z0-9]+)[^"']*)/gi;
  let match;
  while ((match = linkRegex.exec(html)) !== null) {
    const href = match[1];
    const dbname = match[2];
    const filename = match[3];
    const detailURL = href.startsWith("http")
      ? href
      : `https://kns.cnki.net${href.startsWith("/") ? "" : "/"}${href}`;
    if (dbname && filename && !results.find(r => r.filename === filename)) {
      results.push({ dbname, filename, detailURL });
    }
  }

  // 方法2：从 data-filename 属性提取
  const dataRegex = /data-filename=["']([A-Z0-9]+)["'][^>]*data-dbname=["']([A-Z0-9]+)["']/gi;
    while ((match = dataRegex.exec(html)) !== null) {
      const filename = match[1];
      const dbname = match[2];
      if (filename && dbname && !results.find(r => r.filename === filename)) {
      results.push({ dbname, filename, detailURL: null });
      }
    }

  // 方法3：从 onclick 属性中提取
  const onclickRegex = /filename['"]?\s*[:=]\s*['"]([A-Z0-9]+)['"].*?dbname['"]?\s*[:=]\s*['"]([A-Z0-9]+)['"]/gi;
    while ((match = onclickRegex.exec(html)) !== null) {
      const filename = match[1];
      const dbname = match[2];
      if (filename && dbname && !results.find(r => r.filename === filename)) {
      results.push({ dbname, filename, detailURL: null });
      }
    }

  return results;
}

/**
 * 调用知网 Export API 获取 RefWorks / EndNote 格式元数据
 * @param {string} filename - 知网文献唯一标识（如 KXTB202401001）
 * @param {string} dbname - 数据库名称（如 CJFD2024）
 * @param {string[]} debugLog - 调试日志数组
 */
async function fetchCNKIExport(filename, dbname, referer, cookieHeader, debugLog) {
  debugLog.push(`[CNKI-ExportAPI] 请求 filename=${filename} dbname=${dbname} hasCookie=${cookieHeader ? "true" : "false"}`);

  try {
    const body = new URLSearchParams({
      filename: `${dbname}!${filename}!1!0`,
      displaymode: "GBTREFER,elearning,EndNote"
    }).toString();

    const resp = await fetch(CNKI_EXPORT_URL, {
      method: "POST",
      headers: {
        "Accept": "text/plain, */*; q=0.01",
        "Accept-Language": "zh-CN,en-US;q=0.7,en;q=0.3",
        "Content-Type": "application/x-www-form-urlencoded",
        "User-Agent": CNKI_UA,
        "Host": "kns.cnki.net",
        "Referer": referer,
        "Origin": "https://www.cnki.net",
        ...(cookieHeader ? { "Cookie": cookieHeader } : {})
      },
      body,
      signal: AbortSignal.timeout(20000)
    });

    if (!resp.ok) {
      debugLog.push(`[CNKI-ExportAPI] HTTP ${resp.status}，跳过`);
      return null;
    }

    const text = await resp.text();
    debugLog.push(`[CNKI-ExportAPI] 收到响应，长度=${text.length}`);

    const exportText = exportTextFromPayload(text);
    if (!exportText) {
      debugLog.push(`[CNKI-ExportAPI] 无法解析响应内容`);
      return null;
    }

    const parsed = parseRefWorks(exportText);
    if (parsed) {
      debugLog.push(`[CNKI-ExportAPI] 解析成功: "${parsed.title}"`);
      return parsed;
    }

    debugLog.push(`[CNKI-ExportAPI] 响应可解码，但未识别为 RefWorks/EndNote`);
    return null;
  } catch (err) {
    debugLog.push(`[CNKI-ExportAPI] 异常: ${err?.message || err}`);
    return null;
  }
}

/**
 * 通过知网搜索接口搜索文献，再调用 Export API 获取精确元数据。
 * 这条路径尽量对齐原生实现：grid 搜索 + cookie + dm8/API/GetExport。
 */
async function searchCNKIWithExport(title, author, year, fileName, cookieHeader, debugLog) {
  debugLog.push(`[CNKI-Export] 开始知网搜索 | 标题: "${title}" | 作者: "${author || "(无)"}" | 年份: "${year || "(无)"}" | hasCookie=${cookieHeader ? "true" : "false"}`);

  try {
    const searchBody = buildCNKISearchBody({
      title,
      author,
      doi: null,
      fileName: fileName || title
    });
    const referer = cnkiSearchReferer({
      title,
      doi: null,
      fileName: fileName || title
    });

    const resp = await fetch(CNKI_SEARCH_URL, {
      method: "POST",
      headers: {
        "Accept": "*/*",
        "Accept-Language": "zh-CN,en-US;q=0.9,en;q=0.8",
        "Content-Type": "application/x-www-form-urlencoded",
        "User-Agent": CNKI_UA,
        "Host": "kns.cnki.net",
        "X-Requested-With": "XMLHttpRequest",
        "Referer": referer,
        "Origin": "https://kns.cnki.net",
        "Sec-Fetch-Dest": "empty",
        "Sec-Fetch-Mode": "cors",
        ...(cookieHeader ? { "Cookie": cookieHeader } : {})
      },
      body: searchBody,
      signal: AbortSignal.timeout(12000)
    });

    if (resp.status !== 200 && resp.status !== 403) {
      debugLog.push(`[CNKI-Export] 搜索请求失败: HTTP ${resp.status}`);
      return null;
    }

    const html = await resp.text();
    debugLog.push(`[CNKI-Export] 搜索响应长度=${html.length}`);

    // 检测是否触发了人机验证
    if (resp.status === 403 || html.includes("captcha") || html.includes("验证码") || html.includes("安全验证") || html.length < 500) {
      debugLog.push(`[CNKI-Export] 触发反爬/人机验证，跳过知网直接搜索`);
      return null;
    }

    // 从搜索结果 HTML 中提取 filename/dbname
    const params = extractCNKIParams(html);
    debugLog.push(`[CNKI-Export] 提取到 ${params.length} 个文献参数`);

    if (params.length === 0) {
      debugLog.push(`[CNKI-Export] 未能提取到 filename/dbname，知网可能改版`);
      return null;
    }

    // 对前3个结果尝试 Export API
    for (let i = 0; i < Math.min(3, params.length); i++) {
      const { filename, dbname, detailURL } = params[i];
      const exported = await fetchCNKIExport(filename, dbname, detailURL, cookieHeader, debugLog);
      if (exported) {
        // 验证标题相似度
        const sim = titleSimilarity(title, exported.title);
        debugLog.push(`[CNKI-Export] 候选 ${i + 1}: "${exported.title}" | 相似度=${sim.toFixed(3)}`);
        if (sim >= 0.55) {
          debugLog.push(`[CNKI-Export] 相似度达标，使用此结果`);
          exported.url = `https://kns.cnki.net/KCMS/detail/detail.aspx?dbname=${dbname}&filename=${filename}`;
          return exported;
        }
      }
    }

    debugLog.push(`[CNKI-Export] 所有候选相似度不足`);
    return null;
  } catch (err) {
    debugLog.push(`[CNKI-Export] 异常: ${err?.message || err}`);
    return null;
  }
}

// 中文文献专用搜索接口：三层策略
// 策略1: 百度学术 标题+作者精确搜索
// 策略2: 百度学术 仅标题搜索（降级）
// 策略3: 知网 Export API 精确抓取（最高准确率）
async function handleSearchCN(body, response) {
  const title = String(body?.title || "").trim();
  const author = String(body?.author || "").trim();
  const year = body?.year ? String(body.year).trim() : null;
  const fileName = body?.fileName ? String(body.fileName).trim() : null;
  const cookieHeader = normalizeCookieHeader(body?.cookieHeader);
  const debugMode = body?.debug === true;
  const debugLog = [];

  if (!title) {
    json(response, 400, { message: "缺少标题参数。" });
    return;
  }

  debugLog.push(`[SearchCN] 开始搜索 | 标题: "${title}" | 作者: "${author}" | 年份: "${year || "(未提供)"}"`);

  // ═══════════════════════════════════════════════════════
  // 策略 1：百度学术 - 标题 + 作者精确搜索
  // ═══════════════════════════════════════════════════════
  try {
    const baiduQuery1 = author ? `${title} ${author}` : title;
    debugLog.push(`[策略1] 百度学术 标题+作者搜索 | 查询: "${baiduQuery1}"`);

    const results1 = await searchBaiduScholar(baiduQuery1, debugLog);

    if (results1.length > 0) {
      // 找相似度最高的结果
      const scored = results1.map(r => ({
        result: r,
        score: titleSimilarity(title, r.title)
      })).sort((a, b) => b.score - a.score);

      debugLog.push(`[策略1] 相似度评分:`);
      scored.forEach(s => debugLog.push(`  score=${s.score.toFixed(3)} | "${s.result.title}"`));

      const best = scored[0];
      debugLog.push(`[策略1] 最佳候选: score=${best.score.toFixed(3)} | "${best.result.title}"`);

      if (best.score >= 0.55 && best.result.paperId) {
        debugLog.push(`[策略1] 相似度达标，抓取详情页...`);
        const detail = await fetchBaiduDetail(best.result.paperId, debugLog);

        if (detail) {
          const item = baiduMetaToSwiftLibItem(best.result, detail);
          debugLog.push(`[策略1] 成功！最终标题: "${item.title}"`);
          json(response, 200, {
            item,
            strategy: "baidu-title+author",
            debug: debugMode ? debugLog : undefined
          });
          return;
        }
      } else {
        debugLog.push(`[策略1] 相似度不足 (${best.score.toFixed(3)} < 0.55) 或无 paperid，跳过`);
      }
    } else {
      debugLog.push(`[策略1] 百度学术无搜索结果`);
    }
  } catch (err) {
    debugLog.push(`[策略1] 异常: ${err?.message || err}`);
  }

  // ═══════════════════════════════════════════════════════
  // 策略 2：百度学术 - 仅标题搜索（降级）
  // ═══════════════════════════════════════════════════════
  if (author) {
    try {
      debugLog.push(`[策略2] 百度学术 仅标题搜索 | 查询: "${title}"`);
      const results2 = await searchBaiduScholar(title, debugLog);

      if (results2.length > 0) {
        const scored2 = results2.map(r => ({
          result: r,
          score: titleSimilarity(title, r.title)
        })).sort((a, b) => b.score - a.score);

        debugLog.push(`[策略2] 相似度评分:`);
        scored2.forEach(s => debugLog.push(`  score=${s.score.toFixed(3)} | "${s.result.title}"`));

        const best2 = scored2[0];
        debugLog.push(`[策略2] 最佳候选: score=${best2.score.toFixed(3)} | "${best2.result.title}"`);

        if (best2.score >= 0.55 && best2.result.paperId) {
          debugLog.push(`[策略2] 相似度达标，抓取详情页...`);
          const detail2 = await fetchBaiduDetail(best2.result.paperId, debugLog);

          if (detail2) {
            const item2 = baiduMetaToSwiftLibItem(best2.result, detail2);
            debugLog.push(`[策略2] 成功！最终标题: "${item2.title}"`);
            json(response, 200, {
              item: item2,
              strategy: "baidu-title-only",
              debug: debugMode ? debugLog : undefined
            });
            return;
          }
        } else {
          debugLog.push(`[策略2] 相似度不足 (${best2.score.toFixed(3)} < 0.55) 或无 paperid，跳过`);
        }
      } else {
        debugLog.push(`[策略2] 百度学术仅标题搜索无结果`);
      }
    } catch (err) {
      debugLog.push(`[策略2] 异常: ${err?.message || err}`);
    }
  }

  // ═══════════════════════════════════════════════════════
  // 策略 3：知网 Export API 精确抓取（最高准确率，不受改版影响）
  // ═══════════════════════════════════════════════════════
  try {
    debugLog.push(`[策略3] 知网 Export API 搜索 | 标题: "${title}" | 作者: "${author || "(无)"}" | hasCookie=${cookieHeader ? "true" : "false"}`);
    const cnkiExportResult = await searchCNKIWithExport(title, author, year, fileName, cookieHeader, debugLog);
    if (cnkiExportResult) {
      debugLog.push(`[策略3] Export API 成功！标题: "${cnkiExportResult.title}"`);
      json(response, 200, {
        item: cnkiExportResult,
        strategy: "cnki-export-api",
        debug: debugMode ? debugLog : undefined
      });
      return;
    }
    debugLog.push(`[策略3] Export API 无结果`);
  } catch (err) {
    debugLog.push(`[策略3] 异常: ${err?.message || err}`);
  }

  // 全部策略失败
  debugLog.push(`[SearchCN] 全部策略均失败`);
  json(response, 404, {
    message: "所有搜索策略均未找到匹配的中文文献元数据。",
    debug: debugMode ? debugLog : undefined
  });
}

async function handleRefresh(body, response) {
  const reference = body?.reference || {};
  const url = String(reference.url || "").trim();
  const doi = String(reference.doi || "").trim();
  const isbn = String(reference.isbn || "").trim();
  const pmid = String(reference.pmid || "").trim();
  const arxiv = String(reference.arxiv || "").trim();
  const title = String(reference.title || "").trim();
  const authors = (reference.authors || []).map(a => a.family || a.given || "").join(" ").trim();

  if (url.startsWith("http://") || url.startsWith("https://")) {
    await handleResolve({ inputType: "url", value: url }, response);
    return;
  }

  const identifier = doi || isbn || pmid || arxiv;
  if (identifier) {
    await handleResolve({ inputType: "identifier", value: identifier }, response);
    return;
  }

  const query = `${title} ${authors}`.trim();
  if (query) {
    await handleResolve({ inputType: "search", value: query }, response);
    return;
  }

  json(response, 404, { message: "当前条目缺少可刷新的 URL、标识符或标题。" });
}

async function handleUpdateTranslators(response) {
  if (runtimeMode === "external") {
    json(response, 400, {
      ok: false,
      message: "外部 backend 模式下无法从 SwiftLib 更新 translators。"
    });
    return;
  }

  const result = await ensureRuntimeOverlay({ force: true, reason: "manual-update" });
  json(response, 200, {
    ok: true,
    message: result.message,
    translationServerRevision,
    translatorsCNRevision,
    runtimeMode,
    overlayRevision,
    licensesVersion,
    runtimeRoot: result.runtimeRoot,
    updatedAt: result.state?.updatedAt || null
  });
}

function verifyAuthorization(request, response) {
  const authorization = request.headers.authorization || "";
  if (authorization !== `Bearer ${token}`) {
    json(response, 401, { message: "未授权。" });
    return false;
  }
  return true;
}

function readJSONBody(request) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let totalBytes = 0;
    request.on("data", (chunk) => {
      totalBytes += chunk.length;
      if (totalBytes > MAX_REQUEST_BODY_BYTES) {
        request.destroy();
        reject(new Error("Request body too large"));
        return;
      }
      chunks.push(chunk);
    });
    request.on("end", () => {
      const raw = Buffer.concat(chunks).toString("utf8");
      if (!raw) {
        resolve({});
        return;
      }
      try {
        resolve(JSON.parse(raw));
      } catch (error) {
        reject(error);
      }
    });
    request.on("error", reject);
  });
}

const server = http.createServer(async (request, response) => {
  try {
    const url = new URL(request.url || "/", "http://127.0.0.1");

    if (request.method === "GET" && url.pathname === "/health") {
      json(response, 200, { ok: true, version });
      return;
    }

    if (!verifyAuthorization(request, response)) {
      return;
    }

    if (request.method === "GET" && url.pathname === "/capabilities") {
      json(response, 200, {
        translationServerRevision,
        translatorsCNRevision,
        supportedInputs: ["url", "identifier"],
        supportsRefresh: true,
        supportsChineseSearch: true,
        supportsBaiduScholar: true,   // 百度学术适配器已启用（三层降级策略）
        runtimeMode,
        overlayRevision,
        licensesVersion
      });
      return;
    }

    if (request.method === "POST" && url.pathname === "/resolve") {
      await handleResolve(await readJSONBody(request), response);
      return;
    }

    if (request.method === "POST" && url.pathname === "/resolve-selection") {
      await handleResolveSelection(await readJSONBody(request), response);
      return;
    }

    if (request.method === "POST" && url.pathname === "/refresh") {
      await handleRefresh(await readJSONBody(request), response);
      return;
    }

    if (request.method === "POST" && url.pathname === "/search-cn") {
      await handleSearchCN(await readJSONBody(request), response);
      return;
    }

    if (request.method === "POST" && url.pathname === "/maintenance/update-translators") {
      await handleUpdateTranslators(response);
      return;
    }

    json(response, 404, { message: "未找到请求路径。" });
  } catch (error) {
    json(response, 500, { message: error?.message || String(error) });
  }
});

for (const signal of ["SIGINT", "SIGTERM", "SIGHUP"]) {
  process.on(signal, () => {
    if (embeddedTranslationServer) {
      embeddedTranslationServer.kill(signal);
    }
    process.exit(0);
  });
}

server.listen(0, "127.0.0.1", async () => {
  try {
    await ensureEmbeddedTranslationServer();
    const address = server.address();
    const port = typeof address === "object" && address ? address.port : null;
    process.stdout.write(
      JSON.stringify({
        port,
        token,
        version,
        capabilities: {
          translationServerRevision,
          translatorsCNRevision,
          supportedInputs: ["url", "identifier"],
          supportsRefresh: true,
          runtimeMode,
          overlayRevision,
          licensesVersion
        }
      }) + "\n"
    );
  } catch (error) {
    process.stderr.write(`${error?.stack || error}\n`);
    process.exit(1);
  }
});
