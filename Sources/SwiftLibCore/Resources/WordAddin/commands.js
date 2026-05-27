/* global Office, Word, SwiftLibCiteproc, SwiftLibShared, swiftLibApplyParagraphFontFromCitation, swiftLibTryDeleteLightweightGuardAfterCitationCC, swiftLibSyncTypingFormatAfterCitationGuard */

const CMD_SERVER = "http://127.0.0.1:23858";
function _cmdAuthHeaders(extra) {
  const h = Object.assign({}, extra || {});
  if (window.__SWIFTLIB_TOKEN) h["Authorization"] = "Bearer " + window.__SWIFTLIB_TOKEN;
  return h;
}
const CMD_TAG_PREFIX = "swiftlib:v3:";
const CMD_CITE_TAG_PREFIX = "swiftlib:v3:cite:";
const CMD_BIB_TAG_PREFIX = "swiftlib:v3:bib:";
const CMD_BOUNDARY_GUARD_TAG = "swiftlib:v3:boundary-guard";
const CMD_ZERO_WIDTH_SEPARATOR = "\u200C";
const CMD_CC_TITLE_BIB = "SwiftLib Bibliography";
const CMD_CC_TITLE_CITE = "SwiftLib Citation";
const CMD_SWIFTLIB_XML_NS = "http://swiftlib.com/citations";
const CMD_MAX_WORD_CC_TAG_LENGTH = 220;
const CMD_DEFAULT_FETCH_TIMEOUT_MS = 8000;
const CMD_RENDER_FETCH_TIMEOUT_MS = 20000;
const CMD_DEFAULT_BIBLIOGRAPHY_PARAGRAPH_STYLE = "Normal";

/** Share with taskpane when SharedRuntime is active; fall back to local store. */
const cmdPendingCitationPayload = (typeof state !== "undefined" && state.pendingCitationPayload)
  ? state.pendingCitationPayload
  : {};

/** Pre-insert cursor font snapshot → boundary-guard ZWSP (matches taskpane). */
const cmdPendingCitationGuardFormatById = new Map();
const cmdRuntimeLocks = (typeof SwiftLibShared !== "undefined" && SwiftLibShared.runtimeLocks)
  ? SwiftLibShared.runtimeLocks
  : { upsertCitation: false };

Office.onReady(() => {
  if (!window.__swiftLibSharedWithTaskpane) {
    registerCmdSwiftLibContentControlDeletedCleanup();
  }
  if (typeof Office !== "undefined" && Office.actions && typeof Office.actions.associate === "function") {
    Office.actions.associate("insertBibliography", insertBibliography);
    Office.actions.associate("insertCitationCommand", insertCitationCommand);
    Office.actions.associate("refreshAllCommand", refreshAllCommand);
    Office.actions.associate("finalizeToPlainTextCommand", finalizeToPlainTextCommand);
  }
});

function cmdTryTrackedObjectsRemoveAll(ctx) {
  try {
    if (ctx.trackedObjects && typeof ctx.trackedObjects.removeAll === "function") {
      ctx.trackedObjects.removeAll();
    }
  } catch {
    /* ignore */
  }
}

function cmdTryClearCannotDelete(cc) {
  try {
    cc.cannotDelete = false;
  } catch {
    /* ignore */
  }
}

function cmdTrySetPlaceholderEmpty(cc) {
  try {
    cc.placeholderText = "";
  } catch {
    /* ignore */
  }
}

async function cmdDeleteSwiftLibGhostContentControlsInContext(ctx) {
  const controls = ctx.document.contentControls;
  controls.load("items");
  await ctx.sync();
  const items = controls.items;
  const pairs = [];
  for (const cc of items) {
    cc.load("tag");
    const rng = cc.getRange();
    rng.load("text");
    pairs.push({ cc, rng });
  }
  await ctx.sync();

  for (const { cc, rng } of pairs) {
    const tag = cc.tag || "";
    if (!tag.startsWith(CMD_TAG_PREFIX)) continue;
    if (tag.startsWith(CMD_BIB_TAG_PREFIX)) continue;

    const text = rng.text || "";

    if (tag === CMD_BOUNDARY_GUARD_TAG) {
      if (text.trim() === "" || !text.includes(CMD_ZERO_WIDTH_SEPARATOR)) {
        cc.delete(false);
      }
      continue;
    }

    if (tag.startsWith(CMD_CITE_TAG_PREFIX) && text.trim() === "") {
      if (typeof swiftLibTryDeleteLightweightGuardAfterCitationCC === "function") {
        await swiftLibTryDeleteLightweightGuardAfterCitationCC(ctx, cc);
      }
      cc.delete(false);
    }
  }
  await ctx.sync();
}

async function cmdCleanupSwiftLibGhostContentControls() {
  return Word.run(async (ctx) => {
    await cmdDeleteSwiftLibGhostContentControlsInContext(ctx);
  });
}

function scheduleCmdSwiftLibGhostCleanupAfterContentControlDeleted() {
  if (window.__swiftLibCmdCcDelTimer) clearTimeout(window.__swiftLibCmdCcDelTimer);
  window.__swiftLibCmdCcDelTimer = setTimeout(async () => {
    window.__swiftLibCmdCcDelTimer = null;
    try {
      await cmdCleanupSwiftLibGhostContentControls();
    } catch (err) {
      console.warn("SwiftLib commands CC-deleted cleanup:", err);
    }
  }, 350);
}

async function registerCmdSwiftLibContentControlDeletedCleanup() {
  if (typeof Word === "undefined" || typeof Word.run !== "function") return;
  try {
    await Word.run(async (context) => {
      if (context.document.onContentControlDeleted) {
        context.document.onContentControlDeleted.add(scheduleCmdSwiftLibGhostCleanupAfterContentControlDeleted);
      }
      await context.sync();
    });
  } catch (e) {
    console.warn("SwiftLib commands onContentControlDeleted unavailable:", e);
  }
}

async function cmdCaptureFormatSnapshotAtCursor(ctx) {
  try {
    const range = ctx.document.getSelection().getRange();
    range.load("isCollapsed");
    await ctx.sync();
    if (range.isCollapsed === false) {
      try {
        if (Word.CollapseDirection && Word.CollapseDirection.end !== undefined) {
          range.collapse(Word.CollapseDirection.end);
          range.select();
          await ctx.sync();
        }
      } catch (_) {
        /* ignore */
      }
    }
    const font = range.font;
    font.load("bold,italic,name,size,color,underline,subscript,superscript,highlightColor");
    await ctx.sync();
    return {
      bold: font.bold,
      italic: font.italic,
      name: font.name,
      size: font.size,
      color: font.color,
      underline: font.underline,
      subscript: font.subscript,
      superscript: font.superscript,
      highlightColor: font.highlightColor,
    };
  } catch (e) {
    console.warn("SwiftLib commands captureFormatSnapshotAtCursor:", e);
    return null;
  }
}

function cmdApplyFontSnapshotToGuardRange(guardRange, snap) {
  if (!guardRange || !guardRange.font || !snap) return;
  const f = guardRange.font;
  try {
    if (snap.name != null && snap.name !== "") f.name = snap.name;
    if (snap.size != null && typeof snap.size === "number") f.size = snap.size;
    if (snap.bold != null) f.bold = snap.bold;
    if (snap.italic != null) f.italic = snap.italic;
    if (snap.color != null) f.color = snap.color;
    if (snap.underline != null) f.underline = snap.underline;
    if (snap.subscript != null) f.subscript = snap.subscript;
    if (snap.superscript != null) f.superscript = snap.superscript;
    if (snap.highlightColor != null) f.highlightColor = snap.highlightColor;
  } catch (e) {
    console.warn("SwiftLib commands applyFontSnapshotToGuardRange:", e);
  }
}

async function cmdInsertLightweightGuardAfterCitationCC(ctx, citationCC, citationIdForPendingFormat) {
  const afterLoc = cmdRangeAfter();
  const afterRange = citationCC.getRange(afterLoc);
  const insStart =
    typeof Word !== "undefined" && Word.InsertLocation && Word.InsertLocation.start !== undefined
      ? Word.InsertLocation.start
      : "Start";
  afterRange.insertText(CMD_ZERO_WIDTH_SEPARATOR, insStart);
  await ctx.sync();
  let snap = null;
  if (citationIdForPendingFormat) {
    snap = cmdPendingCitationGuardFormatById.get(citationIdForPendingFormat) || null;
    cmdPendingCitationGuardFormatById.delete(citationIdForPendingFormat);
  }
  let guardRange = null;
  try {
    const tail = citationCC.getRange(afterLoc);
    if (typeof tail.getNextTextRange === "function") {
      const unit =
        typeof Word !== "undefined" && Word.MovementUnit && Word.MovementUnit.character !== undefined
          ? Word.MovementUnit.character
          : "Character";
      guardRange = tail.getNextTextRange(unit, false);
      if (guardRange && guardRange.font) {
        cmdApplyFontSnapshotToGuardRange(guardRange, snap);
        if (typeof swiftLibApplyParagraphFontFromCitation === "function") {
          await swiftLibApplyParagraphFontFromCitation(ctx, citationCC, guardRange.font);
        }
        guardRange.font.hidden = true;
        try {
          guardRange.font.size = 1;
        } catch (_) {}
      }
    }
  } catch (e) {
    console.warn("SwiftLib commands lightweight guard font:", e);
  }
  const locAfterRange =
    typeof Word !== "undefined" && Word.RangeLocation && Word.RangeLocation.after !== undefined
      ? Word.RangeLocation.after
      : "After";
  try {
    if (guardRange && typeof guardRange.getRange === "function") {
      const typingRange = guardRange.getRange(locAfterRange);
      typingRange.select();
      if (typeof swiftLibSyncTypingFormatAfterCitationGuard === "function") {
        await swiftLibSyncTypingFormatAfterCitationGuard(ctx, citationCC, typingRange);
      }
    } else {
      citationCC.getRange(afterLoc).select();
      const typingRange = ctx.document.getSelection().getRange();
      if (typeof swiftLibSyncTypingFormatAfterCitationGuard === "function") {
        await swiftLibSyncTypingFormatAfterCitationGuard(ctx, citationCC, typingRange);
      }
    }
  } catch (_) {
    try {
      afterRange.select();
      const typingRange = ctx.document.getSelection().getRange();
      if (typeof swiftLibSyncTypingFormatAfterCitationGuard === "function") {
        await swiftLibSyncTypingFormatAfterCitationGuard(ctx, citationCC, typingRange);
      }
    } catch (_) {}
  }
  await ctx.sync();
}

/** Match taskpane — hop cite / bib / boundary-guard; no `cannotEdit`. */
async function cmdEnsureCaretOutsideSwiftLibAnchors(ctx) {
  const afterLoc = cmdRangeAfter();
  for (let h = 0; h < 8; h++) {
    const parent = ctx.document.getSelection().parentContentControlOrNullObject;
    parent.load("tag");
    await ctx.sync();
    if (parent.isNullObject) return;
    const t = parent.tag || "";
    const inside =
      t.startsWith(CMD_CITE_TAG_PREFIX) ||
      t.startsWith(CMD_BIB_TAG_PREFIX) ||
      t === CMD_BOUNDARY_GUARD_TAG;
    if (!inside) return;
    parent.getRange(afterLoc).select();
    await ctx.sync();
  }
}

function cmdParseTag(tag) {
  return SwiftLibShared.parseTag(tag, CMD_CITE_TAG_PREFIX, CMD_BIB_TAG_PREFIX);
}

function cmdCitationFormattingForPayload(payload, citationID) {
  const formatting = payload?.citationFormatting
    ? { ...payload.citationFormatting }
    : {};
  const superscriptSet = new Set(payload?.superscriptCitationIDs || []);
  if (superscriptSet.has(citationID) && formatting.superscript == null) {
    formatting.superscript = true;
    if (formatting.subscript == null) formatting.subscript = false;
  }
  return Object.values(formatting).some((value) => value !== null && value !== undefined)
    ? formatting
    : null;
}

function cmdIsUsableCitationText(value) {
  return typeof value === "string" && value.trim().length > 0;
}

function cmdMissingCitationTextIDs(payload, citations) {
  const citationTexts = payload?.citationTexts || {};
  return (citations || [])
    .map((c) => c.citationID)
    .filter((id) => id && !cmdIsUsableCitationText(citationTexts[id]));
}

function cmdShouldInsertCitationAsHTML(formatting) {
  if (!formatting) return false;
  return Object.values(formatting).some((value) => value === true);
}

function cmdMakeCitationTag(id, style, ids) {
  return SwiftLibShared.makeCitationTag(CMD_CITE_TAG_PREFIX, id, style, ids);
}

function cmdChooseCitationContentTag(citationID, style, ids) {
  return SwiftLibShared.chooseCitationContentTag(
    CMD_CITE_TAG_PREFIX,
    CMD_MAX_WORD_CC_TAG_LENGTH,
    citationID,
    style,
    ids
  );
}

function cmdMakeBibTag(id, style) {
  return SwiftLibShared.makeBibliographyTag(CMD_BIB_TAG_PREFIX, id, style);
}

function cmdReadCitationFallbackPayload(control) {
  return SwiftLibShared.decodeCitationFallbackPayload(control?.placeholderText || "");
}

function cmdSyncCitationFallbackPlaceholder(cc, parsed, style, ids) {
  if (parsed?.kind === "citation" && parsed.fromShortTag && Array.isArray(ids) && ids.length) {
    SwiftLibShared.trySetCitationFallbackPlaceholder(cc, style, ids);
    return;
  }
  cmdTrySetPlaceholderEmpty(cc);
}

function cmdGenerateUUID() {
  if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") {
    return crypto.randomUUID();
  }
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (ch) => {
    const rand = Math.floor(Math.random() * 16);
    const value = ch === "x" ? rand : (rand & 0x3) | 0x8;
    return value.toString(16);
  });
}

function cmdRangeAfter() {
  return typeof Word !== "undefined" && Word.RangeLocation && Word.RangeLocation.after !== undefined
    ? Word.RangeLocation.after
    : "After";
}

async function cmdFetchJSON(path, options, timeoutMs) {
  const opts = options ? { ...options } : {};
  opts.headers = _cmdAuthHeaders(opts.headers);
  const resp = await cmdFetchWithTimeout(CMD_SERVER + path, opts, timeoutMs || CMD_DEFAULT_FETCH_TIMEOUT_MS);
  if (!resp.ok) {
    const fallback = await resp.text();
    let message = fallback || `HTTP ${resp.status}`;
    try {
      const parsed = JSON.parse(fallback);
      if (parsed && typeof parsed.error === "string" && parsed.error.trim()) {
        message = parsed.error.trim();
      }
    } catch {
      /* keep raw text */
    }
    throw new Error(message);
  }
  return resp.json();
}

async function cmdFetchWithTimeout(url, options, timeoutMs) {
  const controller = typeof AbortController !== "undefined" ? new AbortController() : null;
  const opts = options ? { ...options } : {};
  let timer = null;
  if (controller) {
    opts.signal = controller.signal;
    timer = setTimeout(() => controller.abort(), timeoutMs || CMD_DEFAULT_FETCH_TIMEOUT_MS);
  }
  try {
    return await fetch(url, opts);
  } catch (error) {
    if (error && error.name === "AbortError") {
      throw new Error("SwiftLib 本地服务响应超时，请确认 SwiftLib 应用正在运行后重试。");
    }
    throw error;
  } finally {
    if (timer) clearTimeout(timer);
  }
}

async function cmdGetDefaultStyle() {
  try {
    const styles = await cmdFetchJSON("/api/styles");
    return styles.length ? styles[0].id : "apa";
  } catch {
    return "apa";
  }
}

async function cmdCitationKindForStyle(styleId) {
  try {
    const styles = await cmdFetchJSON("/api/styles");
    const s = styles.find((x) => x.id === styleId);
    return s?.citationKind || "";
  } catch {
    return "";
  }
}

async function cmdFetchRenderPayload(styleId, scanCitations, embeddedItems, options) {
  const scan = { citations: scanCitations };
  const kind = await cmdCitationKindForStyle(styleId);
  const includeBibliography = options?.includeBibliography !== false;
  try {
    if (typeof SwiftLibCiteproc !== "undefined" && SwiftLibCiteproc.renderDocumentPayload) {
      const clientResult = await SwiftLibCiteproc.renderDocumentPayload(styleId, scan, {
        baseURL: CMD_SERVER,
        citationKind: kind,
        embeddedItems: embeddedItems || {},
        includeBibliography,
      });
      const missing = cmdMissingCitationTextIDs(clientResult, scanCitations);
      if (!missing.length) return clientResult;
      console.warn("SwiftLib citeproc (commands) missing citation texts, using server", missing);
    }
  } catch (e) {
    console.warn("SwiftLib citeproc (commands):", e);
  }
  // API fallback: pass embedded items snapshot and rich citationItems for server-side rendering
  const reqCitations = scanCitations.map((c) => ({
    key: c.citationID,
    ids: c.ids,
    position: c.position,
    ...(c.citationItems ? { citationItems: c.citationItems } : {}),
  }));
  const reqBody = { style: styleId, citations: reqCitations };
  reqBody.includeBibliography = includeBibliography;
  if (embeddedItems && Object.keys(embeddedItems).length) reqBody.items = embeddedItems;
  const payload = await cmdFetchJSON("/api/render-document", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(reqBody),
  }, CMD_RENDER_FETCH_TIMEOUT_MS);
  const missing = cmdMissingCitationTextIDs(payload, scanCitations);
  if (missing.length && !payload.error) {
    throw new Error(`渲染结果缺少引文文本：${missing.join(", ")}`);
  }
  return payload;
}

function cmdIsWordApi14() {
  try {
    return (
      typeof Office !== "undefined" &&
      Office.context &&
      Office.context.requirements &&
      Office.context.requirements.isSetSupported("WordApi", "1.4")
    );
  } catch {
    return false;
  }
}

function cmdIsWordApi15() {
  try {
    return (
      typeof Office !== "undefined" &&
      Office.context &&
      Office.context.requirements &&
      Office.context.requirements.isSetSupported("WordApi", "1.5")
    );
  } catch {
    return false;
  }
}

function cmdNormalizeBibliographyParagraphStyle(styleName) {
  const name = String(styleName || "").trim();
  return name || CMD_DEFAULT_BIBLIOGRAPHY_PARAGRAPH_STYLE;
}

function cmdBibliographyParagraphStyleFromSnapshot(snapshot) {
  if (typeof globalThis.swiftLibGetBibliographyParagraphStyle === "function") {
    try {
      return cmdNormalizeBibliographyParagraphStyle(globalThis.swiftLibGetBibliographyParagraphStyle());
    } catch (_) {
      /* fall through to snapshot */
    }
  }
  return cmdNormalizeBibliographyParagraphStyle(
    snapshot?.preferences?.bibliographyStyle || CMD_DEFAULT_BIBLIOGRAPHY_PARAGRAPH_STYLE
  );
}

function cmdIsParagraphStyleType(type) {
  const value = String(type || "").toLowerCase();
  return !value || value === "paragraph" || value.endsWith(".paragraph");
}

async function cmdResolveBibliographyParagraphStyleForDocument(ctx, requestedStyle) {
  const requested = cmdNormalizeBibliographyParagraphStyle(requestedStyle);
  if (requested.toLowerCase() === CMD_DEFAULT_BIBLIOGRAPHY_PARAGRAPH_STYLE.toLowerCase()) {
    return CMD_DEFAULT_BIBLIOGRAPHY_PARAGRAPH_STYLE;
  }
  if (!cmdIsWordApi15() || !ctx?.document?.getStyles) return requested;

  try {
    const style = ctx.document.getStyles().getByNameOrNullObject(requested);
    style.load("nameLocal,type");
    await ctx.sync();
    if (!style.isNullObject && cmdIsParagraphStyleType(style.type)) {
      return cmdNormalizeBibliographyParagraphStyle(style.nameLocal || requested);
    }
  } catch (e) {
    console.warn("SwiftLib commands validate bibliography paragraph style:", e);
  }
  return CMD_DEFAULT_BIBLIOGRAPHY_PARAGRAPH_STYLE;
}

function cmdApplyBibliographyParagraphStyle(para, styleName) {
  const resolved = cmdNormalizeBibliographyParagraphStyle(styleName);
  if (resolved.toLowerCase() === CMD_DEFAULT_BIBLIOGRAPHY_PARAGRAPH_STYLE.toLowerCase()) {
    try {
      para.styleBuiltIn = Word.Style.normal;
      return;
    } catch (_) {
      /* fall back to style name */
    }
  }
  try {
    para.style = resolved;
    return;
  } catch (_) {
    /* fallback below */
  }
  try {
    para.styleBuiltIn = Word.Style.normal;
  } catch (_) {
    /* ignore */
  }
}

function cmdBase64ToUtf8(b64) {
  const bin = atob(b64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return new TextDecoder().decode(bytes);
}

async function cmdLoadSwiftLibCustomXmlParts(ctx) {
  const parts = ctx.document.customXmlParts;
  if (parts && typeof parts.getByNamespace === "function") {
    try {
      const scoped = parts.getByNamespace(CMD_SWIFTLIB_XML_NS);
      scoped.load("items");
      await ctx.sync();
      return scoped.items || [];
    } catch (error) {
      console.warn("SwiftLib commands CustomXmlPart getByNamespace fallback:", error);
    }
  }

  parts.load("items");
  await ctx.sync();
  for (const p of parts.items) p.load("namespaceUri");
  await ctx.sync();
  return parts.items.filter((p) => p.namespaceUri === CMD_SWIFTLIB_XML_NS);
}

async function cmdReadSwiftLibStorage(ctx) {
  if (!cmdIsWordApi14()) return null;
  try {
    const items = await cmdLoadSwiftLibCustomXmlParts(ctx);
    for (const p of items) {
      const xmlProxy = p.getXml();
      await ctx.sync();
      const xml = xmlProxy.value;
      const match = xml.match(/<payload[^>]*encoding="base64"[^>]*>([\s\S]*?)<\/payload>/);
      if (!match) return null;
      return JSON.parse(cmdBase64ToUtf8(match[1].trim()));
    }
  } catch (e) {
    console.warn("cmdReadSwiftLibStorage:", e);
  }
  return null;
}

async function cmdBuildSnapshotCitationMap(ctx) {
  const map = new Map();
  try {
    if (cmdIsWordApi14()) {
      const snap = await cmdReadSwiftLibStorage(ctx);
      if (snap?.citations) {
        // v4: preferences.style; v3 (legacy): snap.style — used as document-level style fallback
        const docStyle = snap?.preferences?.style || snap?.style || "";
        for (const c of snap.citations) {
          const cid = String(c.citationId || "").toLowerCase();
          if (!cid) continue;
          map.set(cid, {
            style: c.style || docStyle,
            ids: Array.isArray(c.refIds) ? c.refIds : [],
            // v4: carry citationItems (rich options: locator/prefix/suffix/suppressAuthor)
            citationItems: Array.isArray(c.citationItems) ? c.citationItems : null,
          });
        }
      }
    }
  } catch (e) {
    console.warn("cmdBuildSnapshotCitationMap:", e);
  }
  for (const [cid, payload] of Object.entries(cmdPendingCitationPayload)) {
    if (payload && Array.isArray(payload.ids) && payload.ids.length) {
      map.set(cid.toLowerCase(), {
        style: payload.style || "",
        ids: payload.ids,
        // v4: carry citationItems from pending payload
        citationItems: Array.isArray(payload.citationItems) ? payload.citationItems : null,
      });
    }
  }
  return map;
}

function cmdCollectScanFromItems(items, snapMap) {
  return SwiftLibShared.collectScanFromItems(items, snapMap, {
    tagPrefix: CMD_TAG_PREFIX,
    parseTag: cmdParseTag,
    readFallbackPayload: cmdReadCitationFallbackPayload,
  });
}

function cmdUtf8ToBase64(str) {
  const bytes = new TextEncoder().encode(str);
  let bin = "";
  for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
  return btoa(bin);
}

function cmdBuildStoragePayloadFromScan(scan, style, bibliographyStyle) {
  return {
    v: 4,
    // Document-level preferences: decoupled from UI state and per-citation style.
    preferences: {
      style,
      bibliographyStyle: cmdNormalizeBibliographyParagraphStyle(bibliographyStyle),
    },
    citations: scan.citations.map((c) => ({
      citationId: c.citationID,
      refIds: c.ids,
      style: c.style,
      position: c.position,
      // v4: rich item options (locator/prefix/suffix/suppressAuthor); null = plain refIds
      citationItems: c.citationItems || null,
    })),
    bibliography: scan.bibControls.length > 0,
  };
}

function cmdBuildStorageXml(payload) {
  const json = JSON.stringify(payload);
  const b64 = cmdUtf8ToBase64(json);
  return `<swiftlib xmlns="${CMD_SWIFTLIB_XML_NS}" version="1"><payload encoding="base64">${b64}</payload></swiftlib>`;
}

async function cmdPersistSwiftLibStorageInContext(ctx, scan, style, bibliographyStyle) {
  if (!cmdIsWordApi14()) return;

  const xml = cmdBuildStorageXml(cmdBuildStoragePayloadFromScan(scan, style, bibliographyStyle));
  const items = await cmdLoadSwiftLibCustomXmlParts(ctx);

  let didUpdate = false;
  for (const p of items) {
    p.setXml(xml);
    didUpdate = true;
    break;
  }
  if (!didUpdate) {
    ctx.document.customXmlParts.add(xml);
  }
  await ctx.sync();
}

function cmdScanStructuralSignature(scan) {
  const ids = scan.citations.map((c) => c.citationID).sort().join("|");
  return `${scan.bibControls.length}|${scan.citations.length}|${ids}`;
}

async function cmdScanDocument() {
  return Word.run(async (ctx) => {
    const controls = ctx.document.contentControls;
    controls.load("items");
    await ctx.sync();
    if (!controls.items.length) {
      cmdTryTrackedObjectsRemoveAll(ctx);
      return { citations: [], bibControls: [] };
    }
    for (const cc of controls.items) cc.load("tag,id,placeholderText");
    await ctx.sync();
    if (!controls.items.some((cc) => (cc.tag || "").startsWith(CMD_TAG_PREFIX))) {
      cmdTryTrackedObjectsRemoveAll(ctx);
      return { citations: [], bibControls: [] };
    }
    const snapMap = await cmdBuildSnapshotCitationMap(ctx);
    const scan = cmdCollectScanFromItems(controls.items, snapMap);
    cmdTryTrackedObjectsRemoveAll(ctx);
    return scan;
  });
}

function cmdRenderBibliographyIntoCC(cc, bibliographyText, bibliographyHtml, paragraphStyle) {
  // Always use plain-text paragraph insertion so each entry receives the selected
  // Word paragraph style rather than inheriting the cursor's surrounding style.
  //
  // bibliographyText now contains only reference entries (no sentinel heading).
  // Both the client citeproc path and server exact CSL path return entries only.
  const text = (bibliographyText || "").replace(/\r\n/g, "\n").replace(/\r/g, "\n");
  const lines = text.split("\n");
  const entries = lines.filter((e) => e.trim().length > 0);
  cc.insertText("", Word.InsertLocation.replace);
  if (entries.length === 0) return;
  let last = null;
  for (let i = 0; i < entries.length; i++) {
    const para = last
      ? last.insertParagraph(entries[i], Word.InsertLocation.after)
      : cc.insertParagraph(entries[i], Word.InsertLocation.start);
    cmdApplyBibliographyParagraphStyle(para, paragraphStyle);
    last = para;
  }
}


let cmdRefreshDocumentBusy = false;
let cmdRefreshDocumentQueued = false;
let cmdDeferredBibliographyRefreshTimer = null;

function cmdScheduleDeferredBibliographyRefresh() {
  if (cmdDeferredBibliographyRefreshTimer) {
    clearTimeout(cmdDeferredBibliographyRefreshTimer);
  }
  cmdDeferredBibliographyRefreshTimer = setTimeout(() => {
    cmdDeferredBibliographyRefreshTimer = null;
    if (cmdRefreshDocumentBusy || cmdRuntimeLocks.upsertCitation) {
      cmdScheduleDeferredBibliographyRefresh();
      return;
    }
    cmdRefreshDocumentFromRibbon({ skipGhostCleanup: true }).catch((error) => {
      console.warn("SwiftLib commands deferred bibliography refresh:", error);
    });
  }, 900);
}

async function cmdRefreshDocumentFromRibbon(options) {
  if (cmdRuntimeLocks.upsertCitation && !(options && options.fromUpsert === true)) {
    cmdRefreshDocumentQueued = true;
    return;
  }
  if (cmdRefreshDocumentBusy) {
    cmdRefreshDocumentQueued = true;
    return;
  }
  cmdRefreshDocumentBusy = true;
  try {
    let nextOptions = options;
    do {
      cmdRefreshDocumentQueued = false;
      const refreshResult = await cmdRefreshDocumentOnce(nextOptions);
      if (refreshResult?.citationIds) {
        for (const cid of refreshResult.citationIds) delete cmdPendingCitationPayload[cid];
      }
      if (refreshResult?.deferredBibliographyRefresh) {
        cmdScheduleDeferredBibliographyRefresh();
      }
      nextOptions = undefined;
    } while (cmdRefreshDocumentQueued);
  } finally {
    cmdRefreshDocumentBusy = false;
  }
}

async function cmdRefreshDocumentOnce(options) {
  const skipGhostCleanup = options && options.skipGhostCleanup === true;
  const trustInitialScan = options && options.fromUpsert === true;
  const includeBibliography = !trustInitialScan;
  return Word.run(async (ctx) => {
      if (!skipGhostCleanup) {
        await cmdDeleteSwiftLibGhostContentControlsInContext(ctx);
      }

      const controls = ctx.document.contentControls;
      controls.load("items");
      await ctx.sync();
      const items = controls.items;
      if (!items.length) {
        cmdTryTrackedObjectsRemoveAll(ctx);
        return null;
      }

      for (const cc of items) cc.load("tag,id,placeholderText");
      await ctx.sync();

      if (!items.some((cc) => (cc.tag || "").startsWith(CMD_TAG_PREFIX))) {
        cmdTryTrackedObjectsRemoveAll(ctx);
        return null;
      }

      // Read snapshot once; used for both citation map and document preferences.style.
      const rawSnap = cmdIsWordApi14() ? await cmdReadSwiftLibStorage(ctx) : null;
      const requestedBibliographyStyle = cmdBibliographyParagraphStyleFromSnapshot(rawSnap);
      const bibliographyParagraphStyle = await cmdResolveBibliographyParagraphStyleForDocument(ctx, requestedBibliographyStyle);
      const snapMap = new Map();
      if (rawSnap?.citations) {
        const docStyle = rawSnap?.preferences?.style || rawSnap?.style || "";
        for (const c of rawSnap.citations) {
          const cid = String(c.citationId || "").toLowerCase();
          if (!cid) continue;
          snapMap.set(cid, { style: c.style || docStyle, ids: Array.isArray(c.refIds) ? c.refIds : [] });
        }
      }
      for (const [cid, payload] of Object.entries(cmdPendingCitationPayload)) {
        if (payload && Array.isArray(payload.ids) && payload.ids.length) {
          snapMap.set(cid.toLowerCase(), { style: payload.style || "", ids: payload.ids });
        }
      }

      const scan = cmdCollectScanFromItems(items, snapMap);
      if (!scan.citations.length && !scan.bibControls.length) {
        cmdTryTrackedObjectsRemoveAll(ctx);
        return null;
      }

      // v4: prefer document preferences.style; v3 fallback: snap.style; last resort: first citation style or API default
      const docPrefsStyle = rawSnap?.preferences?.style || rawSnap?.style || null;
      const style = docPrefsStyle
        || (scan.citations.length && scan.citations[0].style ? scan.citations[0].style : await cmdGetDefaultStyle());

      // v4: pass embedded items snapshot for offline-capable rendering
      const embeddedItems = rawSnap?.items || {};
      const data = await cmdFetchRenderPayload(
        style,
        scan.citations.map((c) => ({
          citationID: c.citationID,
          ids: c.ids,
          position: c.position,
          citationItems: c.citationItems || null,
        })),
        embeddedItems,
        { includeBibliography }
      );
      if (data.error) throw new Error(data.error);

      let finalItems = items;
      let finalScan = scan;
      let payload = data;

      if (!trustInitialScan) {
        const ctrlFresh = ctx.document.contentControls;
        ctrlFresh.load("items");
        await ctx.sync();
        const itemsW = ctrlFresh.items;
        if (!itemsW.length) {
          cmdTryTrackedObjectsRemoveAll(ctx);
          return null;
        }
        for (const cc of itemsW) cc.load("tag,id,placeholderText");
        await ctx.sync();

        const scanW = cmdCollectScanFromItems(itemsW, snapMap);
        if (!scanW.citations.length && !scanW.bibControls.length) {
          cmdTryTrackedObjectsRemoveAll(ctx);
          return null;
        }

        if (cmdScanStructuralSignature(scan) !== cmdScanStructuralSignature(scanW)) {
          const styleW =
            scanW.citations.length && scanW.citations[0].style ? scanW.citations[0].style : style;
          payload = await cmdFetchRenderPayload(
            styleW,
            scanW.citations.map((c) => ({
              citationID: c.citationID,
              ids: c.ids,
              position: c.position,
              citationItems: c.citationItems || null,
            })),
            embeddedItems,
            { includeBibliography }
          );
          if (payload.error) throw new Error(payload.error);
        }
        finalItems = itemsW;
        finalScan = scanW;
      }

      const citationRows = [];
      const resolvedCitationMap = new Map(finalScan.citations.map((citation) => [citation.citationID, citation]));
      let primaryBibCC = null;
      const staleBibCCs = [];

      for (const cc of finalItems) {
        const parsed = cmdParseTag(cc.tag || "");
        if (!parsed) continue;
        if (parsed.kind === "citation") {
          citationRows.push({ cc, parsed, resolved: resolvedCitationMap.get(parsed.id) || null });
        } else if (parsed.kind === "bibliography") {
          if (!primaryBibCC) primaryBibCC = cc;
          else staleBibCCs.push(cc);
        }
      }

      for (const cc of finalItems) {
        const t = cc.tag || "";
        if (!t.startsWith(CMD_TAG_PREFIX)) continue;
        cmdTryClearCannotDelete(cc);
        const parsed = cmdParseTag(t);
        if (!(parsed?.kind === "citation" && parsed.fromShortTag)) cmdTrySetPlaceholderEmpty(cc);
      }

      const pendingCitationFormattingApplications = [];
      for (const row of citationRows) {
        const text = payload.citationTexts?.[row.parsed.id];
        if (cmdIsUsableCitationText(text)) {
          cmdSyncCitationFallbackPlaceholder(
            row.cc,
            row.parsed,
            row.resolved?.style || row.parsed.style || "",
            row.resolved?.ids || row.parsed.ids || []
          );
          const citationFormatting = cmdCitationFormattingForPayload(payload, row.parsed.id);
          const insertedRange = SwiftLibShared.replaceContentControlText(row.cc, text);
          if (typeof SwiftLibShared !== "undefined" && typeof SwiftLibShared.applyCitationFormattingToInsertedRange === "function") {
            SwiftLibShared.applyCitationFormattingToInsertedRange(insertedRange, citationFormatting);
          }
          pendingCitationFormattingApplications.push({
            cc: row.cc,
            insertedRange,
            citationFormatting,
            usedHtmlFormatting: false,
          });
        }
      }

      // Apply citation formatting after ctx.sync() so the CC content is committed
      // and cc.getRange("Content") returns a fresh, stable reference.
      // Even when HTML insertion already carries <sup>/<sub>, we still re-apply the
      // formatting on the CC content range as a host-specific fallback.
      if (pendingCitationFormattingApplications.length) {
        await ctx.sync();
        for (const pending of pendingCitationFormattingApplications) {
          if (!pending.citationFormatting) continue;
          if (typeof SwiftLibShared !== "undefined" && typeof SwiftLibShared.setCitationFormatting === "function") {
            SwiftLibShared.setCitationFormatting(pending.cc, pending.citationFormatting);
          } else if (typeof SwiftLibShared !== "undefined" && typeof SwiftLibShared.setCitationSuperscript === "function") {
            SwiftLibShared.setCitationSuperscript(pending.cc, !!pending.citationFormatting?.superscript);
          } else {
            // Last-resort inline fallback (no SwiftLibShared available)
            try {
              const r = pending.cc.getRange();
              r.font.superscript = !!pending.citationFormatting?.superscript;
              r.font.subscript = !!pending.citationFormatting?.subscript;
            } catch (_) {}
          }
        }
      }

      if (primaryBibCC && (payload.bibliographyHtml || payload.bibliographyText)) {
        cmdTrySetPlaceholderEmpty(primaryBibCC);
        cmdRenderBibliographyIntoCC(primaryBibCC, payload.bibliographyText, payload.bibliographyHtml, bibliographyParagraphStyle);
      }
      for (const stale of staleBibCCs) stale.delete(false);

      try {
        await cmdPersistSwiftLibStorageInContext(ctx, finalScan, style, bibliographyParagraphStyle);
      } catch (persistErr) {
        console.warn("SwiftLib commands CustomXmlPart persist:", persistErr);
      }

      await ctx.sync();
      cmdTryTrackedObjectsRemoveAll(ctx);
      return {
        citationIds: finalScan.citations.map((c) => c.citationID),
        deferredBibliographyRefresh: trustInitialScan && finalScan.bibControls.length > 0,
      };
    });
}

async function cmdMoveOutOfSwiftLibCC(ctx) {
  const afterLoc = cmdRangeAfter();
  for (let h = 0; h < 8; h++) {
    const parent = ctx.document.getSelection().parentContentControlOrNullObject;
    parent.load("tag");
    await ctx.sync();
    if (parent.isNullObject) return;
    const t = parent.tag || "";
    if (!t.startsWith(CMD_TAG_PREFIX)) return;
    parent.getRange(afterLoc).select();
    await ctx.sync();
  }
}

function cmdEscapeXml(text) {
  return String(text || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

// OOXML body for a Word footnote: hidden SwiftLib marker run + visible citation text run.
function cmdBuildFootnoteBodyOoxml(markerTag, citationText) {
  const W = "http://schemas.openxmlformats.org/wordprocessingml/2006/main";
  return (
    `<pkg:package xmlns:pkg="http://schemas.microsoft.com/office/2006/xmlPackage">` +
    `<pkg:part pkg:name="/word/document.xml"` +
    ` pkg:contentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml">` +
    `<pkg:xmlData>` +
    `<w:document xmlns:w="${W}"><w:body><w:p>` +
    `<w:r><w:rPr><w:vanish/></w:rPr><w:t>${cmdEscapeXml(markerTag)}</w:t></w:r>` +
    `<w:r><w:t xml:space="preserve"> ${cmdEscapeXml(citationText)}</w:t></w:r>` +
    `</w:p></w:body></w:document>` +
    `</pkg:xmlData></pkg:part></pkg:package>`
  );
}

async function cmdUpsertCitationFromRibbon(refIds, styleId, citationItems) {
  const style = styleId || (await cmdGetDefaultStyle());
  const citationID = cmdGenerateUUID();
  const tagChoice = cmdChooseCitationContentTag(citationID, style, refIds);
  const tag = tagChoice.tag;
  // Store citationItems (v4 rich options) alongside ids in pending payload
  if (tagChoice.isShort) {
    cmdPendingCitationPayload[citationID] = { style, ids: refIds.slice(), citationItems: citationItems || null };
  } else {
    delete cmdPendingCitationPayload[citationID];
  }
  cmdRuntimeLocks.upsertCitation = true;

  const citationKind = await cmdCitationKindForStyle(style);
  const isNoteStyle = citationKind === "note";

  try {
    if (isNoteStyle) {
      // CSL note style → insert as a real Word footnote.  Pre-render text so the
      // footnote body shows real citation text instead of "[…]".
      let initialText = "…";
      try {
        const preData = await cmdFetchRenderPayload(
          style,
          [{ citationID, ids: refIds, position: 0, citationItems: citationItems || null }],
          {},
          { includeBibliography: false }
        );
        if (preData?.citationTexts?.[citationID]) initialText = preData.citationTexts[citationID];
      } catch (e) {
        console.warn("SwiftLib commands: footnote pre-render skipped:", e);
      }

      await Word.run(async (ctx) => {
        await cmdMoveOutOfSwiftLibCC(ctx);
        const range = ctx.document.getSelection();
        if (typeof range.insertFootnote !== "function") {
          // Host lacks WordApi 1.5 — let downstream fall back to CC path.
          throw new Error("insertFootnote unavailable");
        }
        const noteItem = range.insertFootnote("");
        await ctx.sync();
        try {
          const footnoteOoxml = cmdBuildFootnoteBodyOoxml(tag, initialText);
          noteItem.body.insertOoxml(footnoteOoxml, Word.InsertLocation.replace);
        } catch (ooxmlErr) {
          console.warn("SwiftLib commands: footnote OOXML body failed, using insertText fallback:", ooxmlErr);
          const markerRange = noteItem.body.insertText(tag, Word.InsertLocation.start);
          try { markerRange.font.hidden = true; } catch (_) {}
          noteItem.body.insertText(" " + initialText, Word.InsertLocation.end);
        }
        await ctx.sync();
        await cmdPersistCitationModeInContext(ctx, citationID, refIds, style, citationItems);
        await ctx.sync();
      });
      delete cmdPendingCitationPayload[citationID];
    } else {
      // In-text style → original Content Control path.
      await Word.run(async (ctx) => {
        await cmdMoveOutOfSwiftLibCC(ctx);
        const fmt = await cmdCaptureFormatSnapshotAtCursor(ctx);
        if (fmt) cmdPendingCitationGuardFormatById.set(citationID, fmt);
        const range = ctx.document.getSelection();
        const cc = range.insertContentControl("RichText");
        cc.title = CMD_CC_TITLE_CITE;
        cc.appearance = "Hidden";
        cmdSyncCitationFallbackPlaceholder(cc, { kind: "citation", fromShortTag: tagChoice.isShort }, style, refIds);
        cc.tag = tag;
        try {
          await ctx.sync();
        } catch (e) {
          console.warn("SwiftLib commands: ribbon citation tag sync failed, using short tag", e);
          cc.tag = `${CMD_CITE_TAG_PREFIX}${citationID}`;
          cmdPendingCitationPayload[citationID] = { style, ids: refIds.slice() };
          cmdSyncCitationFallbackPlaceholder(cc, { kind: "citation", fromShortTag: true }, style, refIds);
          await ctx.sync();
        }
        SwiftLibShared.replaceContentControlText(cc, "[…]");
        await ctx.sync();
        try {
          await cmdInsertLightweightGuardAfterCitationCC(ctx, cc, citationID);
        } catch (e) {
          console.warn("SwiftLib commands: lightweight guard skipped:", e);
        }
        try {
          await cmdEnsureCaretOutsideSwiftLibAnchors(ctx);
        } catch (e) {
          console.warn("SwiftLib commands: caret hop skipped:", e);
        }
        await ctx.sync();
      });
      await cmdRefreshDocumentFromRibbon({ skipGhostCleanup: true, fromUpsert: true });
    }
  } catch (e) {
    cmdPendingCitationGuardFormatById.delete(citationID);
    throw e;
  } finally {
    cmdRuntimeLocks.upsertCitation = false;
  }
}

// Persist a single footnote-mode citation into the CustomXmlPart snapshot.
// Must be called inside an existing Word.run context.
async function cmdPersistCitationModeInContext(ctx, citationID, refIds, style, citationItems) {
  if (!cmdIsWordApi14()) return;
  try {
    const rawSnap = await cmdReadSwiftLibStorage(ctx);
    const snap = rawSnap || { v: 4, preferences: { style, citationMode: "footnote" }, items: {}, citations: [], bibliography: false };
    if (!snap.preferences) snap.preferences = {};
    snap.preferences.style = style;
    snap.preferences.citationMode = "footnote";
    const entry = {
      citationId: citationID,
      refIds: refIds.slice(),
      citationItems: citationItems || refIds.map((id) => ({ itemRef: `lib:${id}`, refId: id })),
      style,
    };
    snap.citations = Array.isArray(snap.citations) ? snap.citations.slice() : [];
    const idx = snap.citations.findIndex((c) => String(c.citationId) === String(citationID));
    if (idx >= 0) snap.citations[idx] = Object.assign({}, snap.citations[idx], entry);
    else snap.citations.push(entry);
    const xml = cmdBuildStorageXml(snap);
    const items = await cmdLoadSwiftLibCustomXmlParts(ctx);
    let updated = false;
    for (const p of items) { p.setXml(xml); updated = true; break; }
    if (!updated) ctx.document.customXmlParts.add(xml);
  } catch (e) {
    console.warn("SwiftLib commands: footnote CustomXmlPart persist:", e);
  }
}

// ---------------------------------------------------------------------------
// Ribbon + task pane: Insert / update bibliography block at cursor
// ---------------------------------------------------------------------------

/**
 * @returns {Promise<{ ok: true } | { ok: false, code?: string, message?: string }>}
 */
async function cmdPerformInsertBibliography() {
  try {
    const { citations, style, bibliographyStyle } = await Word.run(async (ctx) => {
      const controls = ctx.document.contentControls;
      controls.load("items");
      await ctx.sync();
      for (const cc of controls.items) cc.load("tag,title,id,placeholderText");
      await ctx.sync();

      if (!controls.items.some((cc) => (cc.tag || "").startsWith(CMD_TAG_PREFIX))) {
        return { citations: [], style: null };
      }

      const rawSnap = cmdIsWordApi14() ? await cmdReadSwiftLibStorage(ctx) : null;
      const snapMap = await cmdBuildSnapshotCitationMap(ctx);
      const scan = cmdCollectScanFromItems(controls.items, snapMap);
      return {
        citations: scan.citations.map((citation) => ({
          citationID: citation.citationID,
          ids: citation.ids,
          style: citation.style,
          position: citation.position,
        })),
        style: scan.citations[0]?.style || null,
        bibliographyStyle: cmdBibliographyParagraphStyleFromSnapshot(rawSnap),
      };
    });

    if (!citations.length) {
      return { ok: false, code: "no_citations" };
    }

    const renderStyle = style || (await cmdGetDefaultStyle());
    const data = await cmdFetchRenderPayload(renderStyle, citations);

    if (data.error) {
      return { ok: false, message: data.error };
    }

    await Word.run(async (ctx) => {
      const bibliographyParagraphStyle = await cmdResolveBibliographyParagraphStyleForDocument(ctx, bibliographyStyle);
      await cmdDeleteSwiftLibGhostContentControlsInContext(ctx);

      const controls = ctx.document.contentControls;
      controls.load("items");
      await ctx.sync();
      for (const cc of controls.items) cc.load("tag,title,id,placeholderText");
      await ctx.sync();

      const resolvedCitationMap = new Map(citations.map((citation) => [citation.citationID, citation]));
      let primaryBibCC = null;
      const staleBibCCs = [];
      const citationCCRows = [];

      for (const cc of controls.items) {
        const tag = cc.tag || "";
        const parsed = cmdParseTag(tag);
        if (!parsed) continue;
        if (parsed.kind === "citation") {
          const rng = cc.getRange();
          rng.load("start");
          citationCCRows.push({ cc, parsed, rng, resolved: resolvedCitationMap.get(parsed.id) || null });
        } else if (parsed.kind === "bibliography") {
          if (!primaryBibCC) primaryBibCC = cc;
          else staleBibCCs.push(cc);
        }
      }
      await ctx.sync();

      if (!primaryBibCC) {
        const bibID = cmdGenerateUUID();
        const bibTag = cmdMakeBibTag(bibID, renderStyle);
        await cmdMoveOutOfSwiftLibCC(ctx);
        const range = ctx.document.getSelection();
        primaryBibCC = range.insertContentControl("RichText");
        primaryBibCC.title = CMD_CC_TITLE_BIB;
        primaryBibCC.tag = bibTag;
        primaryBibCC.appearance = "Hidden";
        cmdTrySetPlaceholderEmpty(primaryBibCC);
        primaryBibCC.insertText("[Bibliography]", Word.InsertLocation.replace);
        await ctx.sync();
      }

      citationCCRows.sort((a, b) => {
        const sa = typeof a.rng.start === "number" ? a.rng.start : 0;
        const sb = typeof b.rng.start === "number" ? b.rng.start : 0;
        return sb - sa;
      });
      const pendingCitationFormattingApplications = [];
      for (const row of citationCCRows) {
        const text = data.citationTexts?.[row.parsed.id];
        if (cmdIsUsableCitationText(text)) {
          cmdSyncCitationFallbackPlaceholder(
            row.cc,
            row.parsed,
            row.resolved?.style || row.parsed.style || "",
            row.resolved?.ids || row.parsed.ids || []
          );
          const citationFormatting = cmdCitationFormattingForPayload(data, row.parsed.id);
          const insertedRange = SwiftLibShared.replaceContentControlText(row.cc, text);
          if (typeof SwiftLibShared !== "undefined" && typeof SwiftLibShared.applyCitationFormattingToInsertedRange === "function") {
            SwiftLibShared.applyCitationFormattingToInsertedRange(insertedRange, citationFormatting);
          }
          pendingCitationFormattingApplications.push({
            cc: row.cc,
            insertedRange,
            citationFormatting,
            usedHtmlFormatting: false,
          });
        }
      }

      // Apply citation formatting after ctx.sync() so the CC content is committed
      // and cc.getRange("Content") returns a fresh, stable reference.
      // Even when HTML insertion already carries <sup>/<sub>, we still re-apply the
      // formatting on the CC content range as a host-specific fallback.
      if (pendingCitationFormattingApplications.length) {
        await ctx.sync();
        for (const pending of pendingCitationFormattingApplications) {
          if (!pending.citationFormatting) continue;
          if (typeof SwiftLibShared !== "undefined" && typeof SwiftLibShared.setCitationFormatting === "function") {
            SwiftLibShared.setCitationFormatting(pending.cc, pending.citationFormatting);
          } else if (typeof SwiftLibShared !== "undefined" && typeof SwiftLibShared.setCitationSuperscript === "function") {
            SwiftLibShared.setCitationSuperscript(pending.cc, !!pending.citationFormatting?.superscript);
          } else {
            // Last-resort inline fallback (no SwiftLibShared available)
            try {
              const r = pending.cc.getRange();
              r.font.superscript = !!pending.citationFormatting?.superscript;
              r.font.subscript = !!pending.citationFormatting?.subscript;
            } catch (_) {}
          }
        }
      }

      if (data.bibliographyHtml || data.bibliographyText) {
        cmdRenderBibliographyIntoCC(primaryBibCC, data.bibliographyText, data.bibliographyHtml, bibliographyParagraphStyle);
      }
      for (const stale of staleBibCCs) stale.delete(false);

      try {
        const bibScan = cmdCollectScanFromItems(controls.items, new Map());
        await cmdPersistSwiftLibStorageInContext(ctx, bibScan, renderStyle, bibliographyParagraphStyle);
      } catch (persistErr) {
        console.warn("SwiftLib commands bib CustomXmlPart persist:", persistErr);
      }

      await ctx.sync();
    });
    return { ok: true };
  } catch (e) {
    console.error("SwiftLib cmdPerformInsertBibliography:", e);
    return { ok: false, message: e.message || String(e) };
  }
}

globalThis.swiftLibPerformInsertBibliography = cmdPerformInsertBibliography;

async function insertBibliography(event) {
  try {
    await cmdPerformInsertBibliography();
  } catch (e) {
    console.error("SwiftLib insertBibliography:", e);
  }
  event.completed();
}

// ---------------------------------------------------------------------------
// Ribbon: Dialog insert / edit citation (Add/Edit Citation)
// ---------------------------------------------------------------------------

/**
 * Detect whether the cursor is currently inside an existing SwiftLib citation
 * content control. Returns { citationID, refIds, style } if so, or null.
 */
async function cmdDetectCursorCitation() {
  try {
    return await Word.run(async (ctx) => {
      const sel = ctx.document.getSelection();
      const parentCC = sel.parentContentControlOrNullObject;
      parentCC.load("tag,placeholderText");
      await ctx.sync();

      if (parentCC.isNullObject) return null;
      const tag = parentCC.tag || "";
      if (!tag.startsWith(CMD_CITE_TAG_PREFIX)) return null;

      const parsed = cmdParseTag(tag);
      if (!parsed || parsed.kind !== "citation") return null;

      let refIds = parsed.ids?.length ? parsed.ids.slice() : [];
      let style = parsed.style || "";

      // Resolve from fallback payload if tag was shortened
      if (parsed.fromShortTag || !refIds.length) {
        const fallback = cmdReadCitationFallbackPayload(parentCC);
        if (fallback?.ids?.length) {
          refIds = fallback.ids.slice();
          style = fallback.style || style;
        }
      }
      // Resolve from snapshot map if still missing
      if (!refIds.length) {
        const snapMap = await cmdBuildSnapshotCitationMap(ctx);
        const row = snapMap.get(parsed.id);
        if (row?.ids?.length) {
          refIds = row.ids.slice();
          style = row.style || style;
        }
      }
      // Resolve from cmdPendingCitationPayload
      if (!refIds.length) {
        const pend = cmdPendingCitationPayload[parsed.id];
        if (pend?.ids?.length) {
          refIds = pend.ids.slice();
          style = pend.style || style;
        }
      }

      if (!refIds.length) return null;
      return { citationID: parsed.id, refIds, style };
    });
  } catch (e) {
    console.warn("SwiftLib cmdDetectCursorCitation:", e);
    return null;
  }
}

/**
 * Update an existing citation CC's refIds and style, then refresh the document.
 * Called when the user confirms an edit in the dialog.
 */
async function cmdUpdateCitationFromRibbon(citationID, refIds, styleId, citationItems) {
  const style = styleId || (await cmdGetDefaultStyle());
  const tagChoice = cmdChooseCitationContentTag(citationID, style, refIds);

  cmdRuntimeLocks.upsertCitation = true;
  try {
    await Word.run(async (ctx) => {
      const controls = ctx.document.contentControls;
      controls.load("items");
      await ctx.sync();
      for (const cc of controls.items) cc.load("tag");
      await ctx.sync();

      const target = controls.items.find((cc) => {
        const t = cc.tag || "";
        if (!t.startsWith(CMD_CITE_TAG_PREFIX)) return false;
        const p = cmdParseTag(t);
        return p?.id === citationID;
      });
      if (!target) return;

      if (tagChoice.isShort) {
        // Preserve citationItems (v4 rich options) in pending payload
        cmdPendingCitationPayload[citationID] = { style, ids: refIds.slice(), citationItems: citationItems || null };
      } else {
        delete cmdPendingCitationPayload[citationID];
      }
      target.tag = tagChoice.tag;
      cmdSyncCitationFallbackPlaceholder(target, { kind: "citation", fromShortTag: tagChoice.isShort }, style, refIds);
      await ctx.sync();
    });
    await cmdRefreshDocumentFromRibbon({ skipGhostCleanup: true, fromUpsert: true });
  } finally {
    cmdRuntimeLocks.upsertCitation = false;
  }
}

function insertCitationCommand(event) {
  // Detect whether cursor is inside an existing citation to decide insert vs edit mode.
  cmdDetectCursorCitation().then((cursorCitation) => {
    let dialogUrl = `${CMD_SERVER}/dialog.html`;
    if (cursorCitation) {
      const params = new URLSearchParams({
        mode: "edit",
        citationId: cursorCitation.citationID,
        refIds: cursorCitation.refIds.join(","),
        style: cursorCitation.style || "",
      });
      dialogUrl = `${CMD_SERVER}/dialog.html?${params.toString()}`;
    }

    Office.context.ui.displayDialogAsync(
      dialogUrl,
      { height: 55, width: 32, displayInIframe: true },
      function (asyncResult) {
        if (asyncResult.status !== Office.AsyncResultStatus.Succeeded) {
          event.completed();
          return;
        }
        const dlg = asyncResult.value;
        dlg.addEventHandler(Office.EventType.DialogMessageReceived, function (arg) {
          let msg;
          try {
            msg = JSON.parse(arg.message);
          } catch {
            return;
          }
          if (msg.action === "cancel") {
            dlg.close();
            return;
          }
          if (msg.action === "insertCitation" && msg.refIds?.length) {
            cmdUpsertCitationFromRibbon(msg.refIds, msg.styleId, msg.citationItems || null)
              .then(() => dlg.close())
              .catch((e) => console.error(e));
          }
          if (msg.action === "updateCitation" && msg.citationId && msg.refIds?.length) {
            cmdUpdateCitationFromRibbon(msg.citationId, msg.refIds, msg.styleId, msg.citationItems || null)
              .then(() => dlg.close())
              .catch((e) => console.error(e));
          }
        });
        dlg.addEventHandler(Office.EventType.DialogEventReceived, function (arg) {
          if (arg.error === 12006) {
            event.completed();
          }
        });
      }
    );
  }).catch((e) => {
    console.error("SwiftLib insertCitationCommand:", e);
    event.completed();
  });
}

async function refreshAllCommand(event) {
  try {
    // Footnote-mode documents have no SwiftLib content controls — the inline scan finds nothing.
    // Detect the marker in CustomXmlPart and tell the user to use the CLI instead.
    let isFootnoteMode = false;
    try {
      isFootnoteMode = await Word.run(async (ctx) => {
        const snap = await cmdReadSwiftLibStorage(ctx);
        cmdTryTrackedObjectsRemoveAll(ctx);
        return snap?.preferences?.citationMode === "footnote";
      });
    } catch (_) {}

    if (isFootnoteMode) {
      try {
        window.alert(
          "此文档使用脚注引文模式。\n\n" +
          "请使用命令行工具刷新引文编号：\n" +
          "  swiftlib refresh-docx 文档.docx\n\n" +
          "保存文件到本地后运行上述命令，再重新打开即可。"
        );
      } catch (_) {}
    } else {
      await cmdRefreshDocumentFromRibbon();
    }
  } catch (e) {
    console.error("SwiftLib refreshAllCommand:", e);
  }
  event.completed();
}

async function cmdFinalizeSwiftLibToPlainTextInContext(ctx) {
  await SwiftLibShared.finalizeToPlainTextInContext(ctx, {
    citeTagPrefix: CMD_CITE_TAG_PREFIX,
    bibTagPrefix: CMD_BIB_TAG_PREFIX,
    xmlNamespace: CMD_SWIFTLIB_XML_NS,
    isBoundaryGuardTag: (tag) => tag === CMD_BOUNDARY_GUARD_TAG,
    deleteLightweightGuardAfterCitationCC: swiftLibTryDeleteLightweightGuardAfterCitationCC,
    isWordApi14: cmdIsWordApi14,
  });
}

function cmdShowFinalizeSuccessDialog() {
  const msg =
    "已转为纯文字定稿。\n\n可以安全分享；SwiftLib 域控件与元数据已从此副本移除。（若需继续可刷新的版本，请使用定稿前另存的文件。）";
  try {
    window.alert(msg);
  } catch (_) {}
}

async function finalizeToPlainTextCommand(event) {
  const ok = window.confirm(
    "将把 SwiftLib 引文、参考文献控件转为正文并删除 SwiftLib 自定义 XML 元数据；之后无法再使用 SwiftLib 刷新引文。\n\n继续后会先保存当前版本；如需恢复可通过「文件 → 浏览版本历史」找回定稿前状态。\n\n是否继续定稿？"
  );
  if (!ok) {
    event.completed();
    return;
  }
  try {
    await Word.run(async (ctx) => {
      try {
        if (ctx.document.save && typeof ctx.document.save === "function") {
          ctx.document.save();
          await ctx.sync();
        }
      } catch (saveErr) {
        console.warn("SwiftLib save before finalize:", saveErr);
      }
      await cmdFinalizeSwiftLibToPlainTextInContext(ctx);
      cmdTryTrackedObjectsRemoveAll(ctx);
    });
    cmdShowFinalizeSuccessDialog();
  } catch (e) {
    console.error("finalizeToPlainTextCommand:", e);
    try {
      window.alert(`定稿失败: ${e.message || e}`);
    } catch (_) {}
  }
  event.completed();
}
