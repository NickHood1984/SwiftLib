/* global Office, Word, SwiftLibCiteproc, SwiftLibShared, swiftLibApplyParagraphFontFromCitation, swiftLibTryDeleteLightweightGuardAfterCitationCC, swiftLibSyncTypingFormatAfterCitationGuard */

const CMD_SERVER = "http://127.0.0.1:23858";
const CMD_TAG_PREFIX = "swiftlib:v3:";
const CMD_CITE_TAG_PREFIX = "swiftlib:v3:cite:";
const CMD_BIB_TAG_PREFIX = "swiftlib:v3:bib:";
const CMD_BOUNDARY_GUARD_TAG = "swiftlib:v3:boundary-guard";
const CMD_ZERO_WIDTH_SEPARATOR = "\u200C";
const CMD_CC_TITLE_BIB = "SwiftLib Bibliography";
const CMD_CC_TITLE_CITE = "SwiftLib Citation";
const CMD_SWIFTLIB_XML_NS = "http://swiftlib.com/citations";
const CMD_MAX_WORD_CC_TAG_LENGTH = 220;

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

async function cmdFetchJSON(path, options) {
  const resp = options ? await fetch(CMD_SERVER + path, options) : await fetch(CMD_SERVER + path);
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

async function cmdFetchRenderPayload(styleId, scanCitations, embeddedItems) {
  const scan = { citations: scanCitations };
  const kind = await cmdCitationKindForStyle(styleId);
  try {
    if (typeof SwiftLibCiteproc !== "undefined" && SwiftLibCiteproc.renderDocumentPayload) {
      return await SwiftLibCiteproc.renderDocumentPayload(styleId, scan, {
        baseURL: CMD_SERVER,
        citationKind: kind,
        embeddedItems: embeddedItems || {},
      });
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
  if (embeddedItems && Object.keys(embeddedItems).length) reqBody.items = embeddedItems;
  const payload = await cmdFetchJSON("/api/render-document", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(reqBody),
  });
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

function cmdBase64ToUtf8(b64) {
  const bin = atob(b64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return new TextDecoder().decode(bytes);
}

async function cmdReadSwiftLibStorage(ctx) {
  if (!cmdIsWordApi14()) return null;
  try {
    const parts = ctx.document.customXmlParts;
    parts.load("items");
    await ctx.sync();
    for (const p of parts.items) p.load("namespaceUri");
    await ctx.sync();
    for (const p of parts.items) {
      if (p.namespaceUri !== CMD_SWIFTLIB_XML_NS) continue;
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

function cmdBuildStoragePayloadFromScan(scan, style) {
  return {
    v: 4,
    // Document-level preferences: decoupled from UI state and per-citation style.
    preferences: {
      style,
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

async function cmdPersistSwiftLibStorageInContext(ctx, scan, style) {
  if (!cmdIsWordApi14()) return;

  const xml = cmdBuildStorageXml(cmdBuildStoragePayloadFromScan(scan, style));
  const parts = ctx.document.customXmlParts;
  parts.load("items");
  await ctx.sync();

  const items = parts.items;
  for (let i = 0; i < items.length; i++) {
    items[i].load("namespaceUri");
  }
  await ctx.sync();

  for (const p of items) {
    if (p.namespaceUri === CMD_SWIFTLIB_XML_NS) {
      p.setXml(xml);
      await ctx.sync();
      return;
    }
  }
  ctx.document.customXmlParts.add(xml);
  await ctx.sync();
}

function cmdScanStructuralSignature(scan) {
  const ids = scan.citations.map((c) => c.citationID).sort().join("|");
  return `${scan.bibControls.length}|${scan.citations.length}|${ids}`;
}

async function cmdScanDocument() {
  return Word.run(async (ctx) => {
    const snapMap = await cmdBuildSnapshotCitationMap(ctx);
    const controls = ctx.document.contentControls;
    controls.load("items");
    await ctx.sync();
    if (!controls.items.length) {
      cmdTryTrackedObjectsRemoveAll(ctx);
      return { citations: [], bibControls: [] };
    }
    for (const cc of controls.items) cc.load("tag,id,placeholderText");
    await ctx.sync();
    const scan = cmdCollectScanFromItems(controls.items, snapMap);
    cmdTryTrackedObjectsRemoveAll(ctx);
    return scan;
  });
}

function cmdRenderBibliographyIntoCC(cc, bibliographyText, bibliographyHtml) {
  // Always use plain-text paragraph insertion so we can force Word.Style.normal
  // on every entry, regardless of the cursor's surrounding heading style.
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
    try { para.styleBuiltIn = Word.Style.normal; } catch (_) {}
    last = para;
  }
}


let cmdRefreshDocumentBusy = false;
let cmdRefreshDocumentQueued = false;

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
      const clearedCitationIds = await cmdRefreshDocumentOnce(nextOptions);
      if (clearedCitationIds) {
        for (const cid of clearedCitationIds) delete cmdPendingCitationPayload[cid];
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
  return Word.run(async (ctx) => {
      if (!skipGhostCleanup) {
        await cmdDeleteSwiftLibGhostContentControlsInContext(ctx);
      }

      // Read snapshot once; used for both citation map and document preferences.style.
      const rawSnap = cmdIsWordApi14() ? await cmdReadSwiftLibStorage(ctx) : null;
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
        embeddedItems
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
            embeddedItems
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
        if (text) {
          cmdSyncCitationFallbackPlaceholder(
            row.cc,
            row.parsed,
            row.resolved?.style || row.parsed.style || "",
            row.resolved?.ids || row.parsed.ids || []
          );
          const citationFormatting = cmdCitationFormattingForPayload(payload, row.parsed.id);
          const citationHtml =
            cmdShouldInsertCitationAsHTML(citationFormatting)
            && typeof SwiftLibShared !== "undefined" && typeof SwiftLibShared.citationHtmlFromTextAndFormatting === "function"
              ? SwiftLibShared.citationHtmlFromTextAndFormatting(text, citationFormatting)
              : null;
          const insertedRange = citationHtml
            ? row.cc.insertHtml(citationHtml, Word.InsertLocation.replace)
            : row.cc.insertText(text, Word.InsertLocation.replace);
          pendingCitationFormattingApplications.push({
            cc: row.cc,
            insertedRange,
            citationFormatting,
            usedHtmlFormatting: !!citationHtml,
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
        cmdRenderBibliographyIntoCC(primaryBibCC, payload.bibliographyText, payload.bibliographyHtml);
      }
      for (const stale of staleBibCCs) stale.delete(false);

      try {
        await cmdPersistSwiftLibStorageInContext(ctx, finalScan, style);
      } catch (persistErr) {
        console.warn("SwiftLib commands CustomXmlPart persist:", persistErr);
      }

      await ctx.sync();
      cmdTryTrackedObjectsRemoveAll(ctx);
      return finalScan.citations.map((c) => c.citationID);
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

  try {
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
      cc.insertText("[…]", Word.InsertLocation.replace);
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
  } catch (e) {
    cmdPendingCitationGuardFormatById.delete(citationID);
    throw e;
  } finally {
    cmdRuntimeLocks.upsertCitation = false;
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
    const { citations, style } = await Word.run(async (ctx) => {
      const snapMap = await cmdBuildSnapshotCitationMap(ctx);
      const controls = ctx.document.contentControls;
      controls.load("items");
      await ctx.sync();
      for (const cc of controls.items) cc.load("tag,title,id,placeholderText");
      await ctx.sync();
      const scan = cmdCollectScanFromItems(controls.items, snapMap);
      return {
        citations: scan.citations.map((citation) => ({
          citationID: citation.citationID,
          ids: citation.ids,
          style: citation.style,
          position: citation.position,
        })),
        style: scan.citations[0]?.style || null,
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
        if (text) {
          cmdSyncCitationFallbackPlaceholder(
            row.cc,
            row.parsed,
            row.resolved?.style || row.parsed.style || "",
            row.resolved?.ids || row.parsed.ids || []
          );
          const citationFormatting = cmdCitationFormattingForPayload(data, row.parsed.id);
          const citationHtml =
            cmdShouldInsertCitationAsHTML(citationFormatting)
            && typeof SwiftLibShared !== "undefined" && typeof SwiftLibShared.citationHtmlFromTextAndFormatting === "function"
              ? SwiftLibShared.citationHtmlFromTextAndFormatting(text, citationFormatting)
              : null;
          const insertedRange = citationHtml
            ? row.cc.insertHtml(citationHtml, Word.InsertLocation.replace)
            : row.cc.insertText(text, Word.InsertLocation.replace);
          pendingCitationFormattingApplications.push({
            cc: row.cc,
            insertedRange,
            citationFormatting,
            usedHtmlFormatting: !!citationHtml,
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
        cmdRenderBibliographyIntoCC(primaryBibCC, data.bibliographyText, data.bibliographyHtml);
      }
      for (const stale of staleBibCCs) stale.delete(false);

      try {
        const bibScan = cmdCollectScanFromItems(controls.items, new Map());
        await cmdPersistSwiftLibStorageInContext(ctx, bibScan, renderStyle);
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
      const snapMap = await cmdBuildSnapshotCitationMap(ctx);
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
    await cmdRefreshDocumentFromRibbon();
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
