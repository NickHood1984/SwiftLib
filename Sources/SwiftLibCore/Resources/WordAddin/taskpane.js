/* global SwiftLibShared, swiftLibApplyParagraphFontFromCitation, swiftLibTryDeleteLightweightGuardAfterCitationCC, swiftLibPerformInsertBibliography, swiftLibSyncTypingFormatAfterCitationGuard */
// Content Control based citation storage (v3)
window.__swiftLibSharedWithTaskpane = true;
const CC_TITLE_CITE = "SwiftLib Citation";
const CC_TITLE_BIB = "SwiftLib Bibliography";
const TAG_PREFIX = "swiftlib:v3:";
const CITE_TAG_PREFIX = "swiftlib:v3:cite:";
const BIB_TAG_PREFIX = "swiftlib:v3:bib:";
/** Zero-width non-joiner inside a tiny Plain Text CC after each citation — keeps caret outside cite CC (Boundary Guard). */
const BOUNDARY_GUARD_TAG = "swiftlib:v3:boundary-guard";
const ZERO_WIDTH_SEPARATOR = "\u200C";

// Document-level JSON snapshot (WordApi 1.4 CustomXmlPart): travels with the .docx, supports repair/sync
// independent of content-control tag quirks. Rendering prefers client citeproc and
// falls back only to the server's exact CSL renderer.
const SWIFTLIB_XML_NS = "http://swiftlib.com/citations";

/** Word rejects overly long content-control tags (InvalidArgument). Short tags need snapshot / pending merge in collectScanFromItems. */
const MAX_WORD_CC_TAG_LENGTH = 220;

const state = {
  selectedIds: new Set(),
  selectedRefs: [],
  allResults: [],
  citedIds: new Set(),
  debounceTimer: null,
  preferredStyle: null,
  /** @type {Record<string, string>} style id → citationKind (numeric | authorDate | note) */
  styleCitationKind: {},
  hasBibliography: false,
  citedCount: 0,
  brokenCCCount: 0,
  activeResultIndex: 0,
  lastQuery: "",
  shouldRefocusSearch: false,
  editingCitationID: null,
  /**
   * True when edit mode was entered automatically because the cursor moved into
   * a citation CC (vs. the user manually selecting refs).  When the cursor later
   * leaves the citation, we auto-exit edit mode only in this case.
   */
  editEnteredBySelection: false,
  /** @type {Record<string, { style: string, ids: number[] }>} citation UUID → payload when CC tag is shortened */
  pendingCitationPayload: {},
};

function debounce(fn, ms) {
  let t = null;
  return (...args) => {
    clearTimeout(t);
    t = setTimeout(() => {
      t = null;
      fn(...args);
    }, ms);
  };
}

/** Insertion-point font snapshot (before citation CC) → applied to boundary-guard ZWSP; avoids flaky “infer from next char” APIs. */
const pendingCitationGuardFormatById = new Map();

/** Step 3: In-memory cache for CustomXmlPart snapshot — avoids repeated IPC reads/writes. */
const swiftLibStorageCache = {
  loaded: false,
  payload: null,
  lastJson: "",
};

/** Coalesce overlapping refresh calls (immediate). */
let refreshDocumentBusy = false;
let refreshDocumentQueued = false;

/** Prevent double-submit while Insert Citation is running. */
let upsertCitationBusy = false;
const runtimeLocks = (typeof SwiftLibShared !== "undefined" && SwiftLibShared.runtimeLocks)
  ? SwiftLibShared.runtimeLocks
  : { upsertCitation: false };

let insertBibliographyFromTaskpaneBusy = false;

/** Optional: debounce rapid triggers (e.g. future doc listeners). */
const debouncedRefreshDocument = debounce(() => {
  refreshDocument();
}, 350);

function tryTrackedObjectsRemoveAll(ctx) {
  try {
    if (ctx.trackedObjects && typeof ctx.trackedObjects.removeAll === "function") {
      ctx.trackedObjects.removeAll();
    }
  } catch {
    /* ignore */
  }
}

/** Let the task pane repaint chips / status before a long Word.run + network refresh. */
function yieldToPaint() {
  return new Promise((resolve) => {
    requestAnimationFrame(() => requestAnimationFrame(() => resolve()));
  });
}

function showLoadingOverlay(text) {
  const overlay = document.getElementById("loadingOverlay");
  const label = document.getElementById("loadingOverlayText");
  if (label && text) label.textContent = text;
  if (overlay) {
    overlay.classList.add("is-visible");
    overlay.setAttribute("aria-busy", "true");
  }
}

function hideLoadingOverlay() {
  const overlay = document.getElementById("loadingOverlay");
  if (overlay) {
    overlay.classList.remove("is-visible");
    overlay.setAttribute("aria-busy", "false");
  }
}

/** Clear citation options panel inputs back to defaults. */
function clearCitationOptionsPanel() {
  const el = (id) => document.getElementById(id);
  if (el("citOptLocator")) el("citOptLocator").value = "";
  if (el("citOptLocatorLabel")) el("citOptLocatorLabel").value = "page";
  if (el("citOptPrefix")) el("citOptPrefix").value = "";
  if (el("citOptSuffix")) el("citOptSuffix").value = "";
  if (el("citOptSuppressAuthor")) el("citOptSuppressAuthor").checked = false;
  const optPanel = document.getElementById("citationOptionsPanel");
  // citationOptionsPanel is now a <details> element; hide it entirely when no refs selected
  if (optPanel) {
    optPanel.style.display = "none";
    optPanel.removeAttribute("open");
  }
}

/** Clear selected refs + chips + edit banner (after successful insert). */
function clearCitationSelectionUI() {
  const tokens = document.getElementById("selectionTokens");
  if (tokens) tokens.replaceChildren();
  state.editingCitationID = null;
  state.selectedIds.clear();
  state.selectedRefs = [];
  clearCitationOptionsPanel();
  updateSelectionUI();
  hideEditBanner();
}

function restoreCitationSelectionUI(refs, idsSet) {
  state.selectedRefs = refs.slice();
  state.selectedIds = new Set(idsSet);
  updateSelectionUI();
}

/** Show a non-blocking status message. Office.js has no native messageBox API. */
function tryInsertMessageBox(message) {
  setStatus(message);
  return true;
}

/**
 * Remove SwiftLib citation/bib content controls (unwrap to plain text) and delete CustomXmlPart snapshot.
 * Legacy boundary-guard CCs are removed entirely (deleteContent true).
 */
async function finalizeSwiftLibToPlainTextInContext(ctx) {
  await SwiftLibShared.finalizeToPlainTextInContext(ctx, {
    citeTagPrefix: CITE_TAG_PREFIX,
    bibTagPrefix: BIB_TAG_PREFIX,
    xmlNamespace: SWIFTLIB_XML_NS,
    isBoundaryGuardTag,
    deleteLightweightGuardAfterCitationCC: swiftLibTryDeleteLightweightGuardAfterCitationCC,
    isWordApi14,
  });
}

function showFinalizeSuccessDialog() {
  const msg =
    "已转为纯文字定稿。\n\n可以安全分享；SwiftLib 域控件与元数据已从此副本移除。（若需继续可刷新的版本，请使用定稿前另存的文件。）";
  try {
    window.alert(msg);
  } catch (_) {}
}

async function finalizeToPlainText() {
  const ok = window.confirm(
    "将把 SwiftLib 引文、参考文献控件转为正文并删除 SwiftLib 自定义 XML 元数据；之后无法再使用 SwiftLib 刷新引文。\n\n继续后会先保存当前版本；如需恢复可通过「文件 → 浏览版本历史」找回定稿前状态。\n\n是否继续定稿？"
  );
  if (!ok) return;
  try {
    setStatus("正在定稿…");
    await Word.run(async (ctx) => {
      try {
        if (ctx.document.save && typeof ctx.document.save === "function") {
          ctx.document.save();
          await ctx.sync();
        }
      } catch (saveErr) {
        console.warn("SwiftLib save before finalize:", saveErr);
      }
      await finalizeSwiftLibToPlainTextInContext(ctx);
      tryTrackedObjectsRemoveAll(ctx);
    });
    swiftLibStorageCache.loaded = false;
    swiftLibStorageCache.payload = null;
    swiftLibStorageCache.lastJson = "";
    setStatus("已定稿为纯文字。");
    showFinalizeSuccessDialog();
    await refreshCitedIds();
    await refreshBibliographySummary();
    await refreshPaneData();
    updateSelectionUI();
  } catch (e) {
    console.warn("finalizeToPlainText:", e);
    setStatus(`定稿失败: ${e.message || e}`);
  }
}

const debouncedHydrateFromSelection = debounce(async () => {
  try {
    await hydrateFromSelection();
  } catch (e) {
    console.warn("SwiftLib selection change hydrate:", e);
  }
}, 400);

/**
 * Restore the citation style that was last used in this document from
 * the CustomXmlPart snapshot.  Must run before loadStyles() so that
 * state.preferredStyle is set when the <select> is populated.
 */
async function restoreStyleFromDocument() {
  try {
    if (!isWordApi14()) return;
    await Word.run(async (ctx) => {
      const snap = await readSwiftLibStorage(ctx);
      tryTrackedObjectsRemoveAll(ctx);
      // v4: preferences.style; v3 (legacy): snap.style — both are supported
      const restoredStyle = snap?.preferences?.style || snap?.style || null;
      if (restoredStyle) {
        state.preferredStyle = restoredStyle;
      }
    });
  } catch (e) {
    console.warn("restoreStyleFromDocument:", e);
  }
}

async function registerSelectionChangeHandler() {
  if (typeof Word === "undefined" || typeof Word.run !== "function") return;
  try {
    await Word.run(async (context) => {
      if (context.document.onSelectionChanged) {
        context.document.onSelectionChanged.add(debouncedHydrateFromSelection);
      }
      await context.sync();
    });
  } catch (e) {
    console.warn("SwiftLib onSelectionChanged unavailable:", e);
  }
}

Office.onReady(async () => {
  bindEvents();
  await restoreStyleFromDocument();
  await loadStyles();
  await preloadSwiftLibCiteprocForCurrentStyle();
  await clearSwiftLibCitationCannotDeleteLocks();
  await registerSwiftLibContentControlDeletedCleanup();
  await registerSelectionChangeHandler();
  await refreshCitedIds();
  await hydrateFromSelection();
  await refreshPaneData();
  requestSearchFocus();
});

function bindEvents() {
  const searchInput = document.getElementById("searchInput");
  if (searchInput) {
    searchInput.addEventListener("input", onSearchInput);
    searchInput.addEventListener("keydown", onSearchKeyDown);
  }

  document.getElementById("primaryBtn").addEventListener("click", runPrimaryAction);
  const insertBibBtn = document.getElementById("insertBibBtn");
  if (insertBibBtn) insertBibBtn.addEventListener("click", () => insertBibliographyFromTaskpane());
  document.getElementById("refreshBtn").addEventListener("click", () => { closeOverflowMenu(); repairAndRefresh(); });
  const toggleCiteMarksBtn = document.getElementById("toggleCiteMarksBtn");
  if (toggleCiteMarksBtn) toggleCiteMarksBtn.addEventListener("click", () => { closeOverflowMenu(); toggleCitationMarks(); });
  const finalizeBtn = document.getElementById("finalizeBtn");
  if (finalizeBtn) finalizeBtn.addEventListener("click", () => { closeOverflowMenu(); finalizeToPlainText(); });
  document.getElementById("styleSelect").addEventListener("change", onStyleChange);
  document.getElementById("editCancelBtn").addEventListener("click", cancelEditMode);

  // Overflow menu toggle
  const overflowBtn = document.getElementById("overflowBtn");
  if (overflowBtn) {
    overflowBtn.addEventListener("click", (e) => {
      e.stopPropagation();
      toggleOverflowMenu();
    });
  }
  document.addEventListener("click", closeOverflowMenu);

  // Style Manager
  initStyleManager();
}

function toggleOverflowMenu() {
  const menu = document.getElementById("overflowMenu");
  if (menu) menu.classList.toggle("is-open");
}

function closeOverflowMenu() {
  const menu = document.getElementById("overflowMenu");
  if (menu) menu.classList.remove("is-open");
}

function onSearchInput(event) {
  clearTimeout(state.debounceTimer);
  state.debounceTimer = setTimeout(() => search(event.target.value), 120);
}

function onSearchKeyDown(event) {
  if (event.key === "ArrowDown") {
    event.preventDefault();
    moveActiveResult(1);
    return;
  }

  if (event.key === "ArrowUp") {
    event.preventDefault();
    moveActiveResult(-1);
    return;
  }

  if (event.key === "Enter") {
    event.preventDefault();
    if (state.allResults.length && event.target.value.trim()) {
      addActiveResult();
      return;
    }
    if (state.selectedIds.size) upsertCitation();
    return;
  }

  if (event.key === "Backspace" && !event.target.value && state.selectedRefs.length) {
    event.preventDefault();
    removeSelectedId(state.selectedRefs[state.selectedRefs.length - 1].id);
  }
}

function onStyleChange() {
  const newStyle = document.getElementById("styleSelect").value;
  state.preferredStyle = newStyle;

  // Immediately update the in-memory cache so that the next refresh reads
  // the new style from preferences rather than the stale cached value.
  if (swiftLibStorageCache.loaded && swiftLibStorageCache.payload) {
    if (!swiftLibStorageCache.payload.preferences) {
      swiftLibStorageCache.payload.preferences = {};
    }
    swiftLibStorageCache.payload.preferences.style = newStyle;
    // Also clear the lastJson sentinel so the next persist actually writes.
    swiftLibStorageCache.lastJson = "";
  }

  preloadSwiftLibCiteprocForCurrentStyle();
  // Re-render existing citations with the new style and persist the
  // choice into the document's CustomXmlPart so it survives reopen.
  debouncedRefreshDocument();
}

function showEditBanner(label) {
  const banner = document.getElementById("editBanner");
  const text = document.getElementById("editBannerText");
  if (banner) banner.classList.remove("hidden");
  if (text) text.textContent = label || "正在编辑引文";
  const btn = document.getElementById("primaryBtn");
  if (btn) btn.textContent = "更新引文";
}

function hideEditBanner() {
  const banner = document.getElementById("editBanner");
  if (banner) banner.classList.add("hidden");
  updatePrimaryButton();
}

function cancelEditMode() {
  state.editingCitationID = null;
  state.editEnteredBySelection = false;
  state.selectedIds.clear();
  state.selectedRefs = [];
  clearCitationOptionsPanel();
  updateSelectionUI();
  hideEditBanner();
  requestSearchFocus();
}

function isWordApi14() {
  try {
    return (
      typeof Office !== "undefined" &&
      Office.context &&
      Office.context.requirements &&
      Office.context.requirements.isSetSupported("WordApi", "1.4")
    );
  } catch (e) {
    return false;
  }
}

function utf8ToBase64(str) {
  const bytes = new TextEncoder().encode(str);
  let bin = "";
  for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
  return btoa(bin);
}

function buildStoragePayloadFromScan(scan, style) {
  // Merge existing items snapshot from cache with any new items from scan.
  // This ensures CSL snapshots accumulate across refreshes rather than being lost.
  const existingItems = swiftLibStorageCache.payload?.items || {};
  const mergedItems = Object.assign({}, existingItems);
  // Incorporate any new item snapshots provided by scan (populated during upsert)
  if (scan.itemSnapshots) {
    for (const [key, val] of Object.entries(scan.itemSnapshots)) {
      mergedItems[key] = val;
    }
  }
  return {
    v: 4,
    // Document-level preferences: decoupled from UI state and per-citation style.
    // Only updated when the user explicitly changes the style (onStyleChange),
    // not on every refresh. This prevents UI state from polluting the document.
    preferences: {
      style,
    },
    // CSL JSON snapshots keyed by docItemKey ("lib:<refId>" or "doi:<doi>" or "uuid:<uuid>").
    // Allows the document to be refreshed without the local library.
    items: mergedItems,
    citations: scan.citations.map((c) => ({
      citationId: c.citationID,
      // citationItems carries the full item options model (locator, prefix, suffix, etc.)
      // Falls back to legacy refIds for backward compatibility.
      citationItems: c.citationItems || c.ids.map((id) => ({ itemRef: `lib:${id}`, refId: id })),
      // Keep refIds for backward compatibility with v3 readers
      refIds: c.ids,
      style: c.style,
      position: c.position,
    })),
    bibliography: scan.bibControls.length > 0,
  };
}

function buildStorageXml(payload) {
  const json = JSON.stringify(payload);
  const b64 = utf8ToBase64(json);
  return `<swiftlib xmlns="${SWIFTLIB_XML_NS}" version="1"><payload encoding="base64">${b64}</payload></swiftlib>`;
}

/**
 * Writes the SwiftLib snapshot into a CustomXmlPart (single part per document, namespace SWIFTLIB_XML_NS).
 * Must run inside an existing Word.run(ctx) — queues setXml/add; caller syncs.
 */
async function persistSwiftLibStorageInContext(ctx, scan, style, rawPayload) {
  if (!isWordApi14()) return;

  // rawPayload: if provided (e.g. from relink), use directly instead of rebuilding from scan
  const storagePayload = rawPayload || buildStoragePayloadFromScan(scan, style);
  const json = JSON.stringify(storagePayload);

  // Skip write if payload unchanged since last persist
  if (swiftLibStorageCache.lastJson === json) {
    return;
  }

  const xml = buildStorageXml(storagePayload);
  const parts = ctx.document.customXmlParts;
  parts.load("items");
  await ctx.sync();

  const items = parts.items;
  for (let i = 0; i < items.length; i++) {
    items[i].load("namespaceUri");
  }
  await ctx.sync();

  for (const p of items) {
    if (p.namespaceUri === SWIFTLIB_XML_NS) {
      p.setXml(xml);
      // Let the outer ctx.sync() flush this write instead of an extra sync here
      break;
    }
  }
  if (!items.length || !Array.from(items).some(p => p.namespaceUri === SWIFTLIB_XML_NS)) {
    ctx.document.customXmlParts.add(xml);
  }

  // Update in-memory cache
  swiftLibStorageCache.loaded = true;
  swiftLibStorageCache.payload = storagePayload;
  swiftLibStorageCache.lastJson = json;
}

// ---------------------------------------------------------------------------
// CustomXmlPart — read back + reconcile
// ---------------------------------------------------------------------------

function base64ToUtf8(b64) {
  const bin = atob(b64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return new TextDecoder().decode(bytes);
}

/**
 * Reads and decodes the SwiftLib CustomXmlPart snapshot.
 * Must run inside an existing Word.run(ctx). Returns the parsed payload object
 * { v, style, citations: [{citationId, refIds, style, position}], bibliography }
 * or null if no part found or decoding fails.
 */
async function readSwiftLibStorage(ctx) {
  if (!isWordApi14()) return null;
  try {
    const parts = ctx.document.customXmlParts;
    parts.load("items");
    await ctx.sync();
    for (const p of parts.items) p.load("namespaceUri");
    await ctx.sync();
    for (const p of parts.items) {
      if (p.namespaceUri !== SWIFTLIB_XML_NS) continue;
      const xmlProxy = p.getXml();
      await ctx.sync();
      const xml = xmlProxy.value;
      const match = xml.match(/<payload[^>]*encoding="base64"[^>]*>([\s\S]*?)<\/payload>/);
      if (!match) return null;
      return JSON.parse(base64ToUtf8(match[1].trim()));
    }
  } catch (e) {
    console.warn("readSwiftLibStorage:", e);
  }
  return null;
}

async function buildSnapshotCitationMap(ctx) {
  const map = new Map();
  try {
    if (isWordApi14()) {
      let snap = null;
      if (swiftLibStorageCache.loaded) {
        snap = swiftLibStorageCache.payload;
      } else {
        snap = await readSwiftLibStorage(ctx);
        swiftLibStorageCache.loaded = true;
        swiftLibStorageCache.payload = snap;
      }
      if (snap?.citations) {
        for (const c of snap.citations) {
          const cid = String(c.citationId || "").toLowerCase();
          if (!cid) continue;
          map.set(cid, {
            style: c.style || "",
            ids: Array.isArray(c.refIds) ? c.refIds : [],
            // v4: carry citationItems (rich options: locator/prefix/suffix/suppressAuthor)
            citationItems: Array.isArray(c.citationItems) ? c.citationItems : null,
          });
        }
      }
    }
  } catch (e) {
    console.warn("SwiftLib buildSnapshotCitationMap:", e);
  }
  for (const [cid, payload] of Object.entries(state.pendingCitationPayload)) {
    if (payload && Array.isArray(payload.ids) && payload.ids.length) {
      map.set(cid.toLowerCase(), {
        style: payload.style || "",
        ids: payload.ids,
        // v4: carry citationItems from pending payload (set during upsertCitation)
        citationItems: Array.isArray(payload.citationItems) ? payload.citationItems : null,
      });
    }
  }
  return map;
}

/**
 * Scans the document and returns three categories of content controls:
 *   valid   — SwiftLib CC whose tag parses correctly
 *   broken  — SwiftLib CC whose tag has the right prefix but fails to parse
 *   ghost   — entries in the CustomXmlPart snapshot with no matching CC in the document
 *
 * Returns { valid, broken, ghost, snapshot }
 */
async function reconcileDocument() {
  return Word.run(async (ctx) => {
    await deleteSwiftLibGhostContentControlsInContext(ctx);

    const controls = ctx.document.contentControls;
    controls.load("items");
    await ctx.sync();
    for (const cc of controls.items) cc.load("tag,id,placeholderText");
    await ctx.sync();

    const snapshot = await readSwiftLibStorage(ctx);
    const snapshotIds = new Set((snapshot?.citations || []).map((c) => c.citationId));

    const valid = [];
    const broken = [];

    for (const cc of controls.items) {
      const tag = cc.tag || "";
      const isSwiftCite = tag.startsWith(CITE_TAG_PREFIX);
      const isSwiftBib = tag.startsWith(BIB_TAG_PREFIX);
      if (!isSwiftCite && !isSwiftBib) continue;

      const parsed = parseTag(tag);
      if (parsed) {
        valid.push({ cc, parsed });
      } else {
        broken.push(cc);
      }
    }

    const validCitationIds = new Set(valid.filter((v) => v.parsed.kind === "citation").map((v) => v.parsed.id));
    const ghost = (snapshot?.citations || []).filter((c) => !validCitationIds.has(c.citationId));

    const boundaryPairs = [];
    for (const cc of controls.items) {
      const tag = cc.tag || "";
      if (!isBoundaryGuardTag(tag)) continue;
      const rng = cc.getRange();
      rng.load("text");
      boundaryPairs.push({ cc, rng });
    }
    await ctx.sync();
    for (const { cc, rng } of boundaryPairs) {
      const t = rng.text || "";
      if (!t.includes(ZERO_WIDTH_SEPARATOR)) {
        broken.push(cc);
      }
    }

    tryTrackedObjectsRemoveAll(ctx);
    return { valid, broken, ghost, snapshot };
  });
}

/** After user deletes a content control, remove any empty cite/guard shells (debounced). */
function scheduleSwiftLibGhostCleanupAfterContentControlDeleted() {
  if (window.__swiftLibCcDelTimer) clearTimeout(window.__swiftLibCcDelTimer);
  window.__swiftLibCcDelTimer = setTimeout(async () => {
    window.__swiftLibCcDelTimer = null;
    try {
      await cleanupSwiftLibGhostContentControls();
      await refreshCitedIds();
      await refreshBibliographySummary();
      await refreshPaneData();
      updateSelectionUI();
    } catch (err) {
      console.warn("SwiftLib CC-deleted cleanup:", err);
    }
  }, 350);
}

async function registerSwiftLibContentControlDeletedCleanup() {
  if (typeof Word === "undefined" || typeof Word.run !== "function") return;
  try {
    await Word.run(async (context) => {
      if (context.document.onContentControlDeleted) {
        context.document.onContentControlDeleted.add(scheduleSwiftLibGhostCleanupAfterContentControlDeleted);
      }
      await context.sync();
    });
  } catch (e) {
    console.warn("SwiftLib onContentControlDeleted unavailable:", e);
  }
}

async function refreshPaneData() {
  await refreshBibliographySummary();
  if (state.lastQuery.trim()) {
    await search(state.lastQuery);
  } else {
    clearSearchResultsPlaceholder();
  }
}

/** No search query — show clean empty state (no API call, no performance cost) */
async function clearSearchResultsPlaceholder() {
  state.allResults = [];
  state.activeResultIndex = -1;
  const label = document.getElementById("recentLabel");
  if (label) label.style.display = "none";
  document.getElementById("results").innerHTML = `
    <div class="empty">
      <div class="empty-title">搜索你的文献库</div>
      <div class="empty-copy">输入标题、作者或年份关键词，快速挑选需要插入的来源。</div>
    </div>
  `;
  setStatus("");
  updatePrimaryButton();
}

async function loadStyles() {
  try {
    const styles = await fetchJSON("/api/styles");
    state.styleCitationKind = {};
    for (const s of styles) {
      state.styleCitationKind[s.id] = s.citationKind || "authorDate";
    }
    const select = document.getElementById("styleSelect");
    select.innerHTML = styles
      .map((s) => `<option value="${s.id}">${escapeHtml(s.title)}${s.builtin === "false" ? " (CSL)" : ""}</option>`)
      .join("");
    if (state.preferredStyle) select.value = state.preferredStyle;
  } catch (error) {
    setStatus(`Cannot load citation styles: ${error.message}`);
  }
}

/** Prime CSL + locale + Engine for current style (reduces first insert/refresh latency). */
async function preloadSwiftLibCiteprocForCurrentStyle() {
  try {
    const sel = document.getElementById("styleSelect");
    if (!sel || !sel.options.length) return;
    const sid = sel.value || "apa";
    const kind = state.styleCitationKind[sid] || "";
    if (typeof SwiftLibCiteproc !== "undefined" && SwiftLibCiteproc.preloadStyleAndLocale) {
      await SwiftLibCiteproc.preloadStyleAndLocale(sid, { baseURL: "", citationKind: kind });
    }
  } catch (e) {
    console.warn("SwiftLib citeproc preload:", e);
  }
}

/**
 * Client citeproc (SwiftLibCiteproc) when available; otherwise use the server's
 * exact CSL renderer. Near-match/native fallback rendering is intentionally disabled.
 *
 * When the document snapshot contains embedded CSL item data (`items`), it is passed
 * to both the client-side citeproc and the server, enabling refresh without the local library.
 */
async function fetchDocumentRenderPayload(styleId, scan) {
  const kind = state.styleCitationKind[styleId] || "";
  // Collect embedded item snapshots from the document (v4 schema)
  const embeddedItems = swiftLibStorageCache.payload?.items || {};
  try {
    if (typeof SwiftLibCiteproc !== "undefined" && SwiftLibCiteproc.renderDocumentPayload) {
      return await SwiftLibCiteproc.renderDocumentPayload(styleId, scan, {
        baseURL: "",
        citationKind: kind,
        embeddedItems,
      });
    }
  } catch (e) {
    console.warn("SwiftLib client citeproc failed, using server:", e);
  }

  const reqCitations = scan.citations.map((c) => ({
    key: c.citationID,
    ids: c.ids,
    position: c.position,
    // Pass citation item options to server for future use
    citationItems: c.citationItems || null,
  }));

  // Use a raw fetch (not fetchJSON) so that a 422 response from the server
  // — which carries { error, orphanIds } for items deleted from the library —
  // is returned as a parsed object instead of thrown.  The caller checks
  // data.error and can still present the orphan banner using data.orphanIds.
  const rawResp = await fetch("/api/render-document", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...(window.__SWIFTLIB_TOKEN ? { "Authorization": "Bearer " + window.__SWIFTLIB_TOKEN } : {}),
    },
    body: JSON.stringify({
      style: styleId,
      citations: reqCitations,
      // Pass embedded items to server so it can render without DB lookup when available
      items: Object.keys(embeddedItems).length ? embeddedItems : undefined,
    }),
  });
  const payload = await rawResp.json();
  // For unexpected errors (not 422 orphan case), surface as thrown error
  if (!rawResp.ok && !Array.isArray(payload.orphanIds)) {
    throw new Error(payload.error || `HTTP ${rawResp.status}`);
  }
  return payload;
}

// ---------------------------------------------------------------------------
// Tag format (v3 — Content Control based):
//   Citation:     swiftlib:v3:cite:<UUID>:<STYLE>:<IDS csv>
//   Short cite:   swiftlib:v3:cite:<UUID>  (Word tag length limit; merge via snapshot + pending)
//   Bibliography: swiftlib:v3:bib:<UUID>:<STYLE>
// ---------------------------------------------------------------------------

function parseCitationTag(tag) {
  return SwiftLibShared.parseCitationTag(tag, CITE_TAG_PREFIX);
}

function parseBibliographyTag(tag) {
  return SwiftLibShared.parseBibliographyTag(tag, BIB_TAG_PREFIX);
}

function parseTag(tag) {
  return SwiftLibShared.parseTag(tag, CITE_TAG_PREFIX, BIB_TAG_PREFIX);
}

function citationFormattingForPayload(payload, citationID) {
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

function shouldInsertCitationAsHTML(formatting) {
  if (!formatting) return false;
  return Object.values(formatting).some((value) => value === true);
}

function makeCitationTag(id, style, ids) {
  return SwiftLibShared.makeCitationTag(CITE_TAG_PREFIX, id, style, ids);
}

/**
 * @returns {{ tag: string, isShort: boolean }}
 */
function chooseCitationContentTag(citationID, style, ids) {
  return SwiftLibShared.chooseCitationContentTag(
    CITE_TAG_PREFIX,
    MAX_WORD_CC_TAG_LENGTH,
    citationID,
    style,
    ids
  );
}

function makeBibliographyTag(id, style) {
  return SwiftLibShared.makeBibliographyTag(BIB_TAG_PREFIX, id, style);
}

function readCitationFallbackPayloadFromControl(control) {
  return SwiftLibShared.decodeCitationFallbackPayload(control?.placeholderText || "");
}

function syncCitationFallbackPlaceholder(cc, parsed, style, ids) {
  if (parsed?.kind === "citation" && parsed.fromShortTag && Array.isArray(ids) && ids.length) {
    SwiftLibShared.trySetCitationFallbackPlaceholder(cc, style, ids);
    return;
  }
  trySetPlaceholderEmpty(cc);
}

function isBoundaryGuardTag(tag) {
  return (tag || "") === BOUNDARY_GUARD_TAG;
}

/** Older builds set cannotDelete on cite/guard CCs; clear so Delete/Backspace works in existing documents. */
function tryClearCannotDelete(cc) {
  try {
    cc.cannotDelete = false;
  } catch {
    /* ignore */
  }
}

/** Empty string removes Word’s default “click or type here” placeholder (esp. Chinese Word for Mac). */
function trySetPlaceholderEmpty(cc) {
  try {
    cc.placeholderText = "";
  } catch {
    /* ignore — older hosts */
  }
}

/**
 * Delete empty citation shells and broken/empty boundary guards (Chinese Word “ghost” placeholders).
 * Does not remove bibliography CCs. Valid guards keep exactly U+200C — not deleted.
 */
async function deleteSwiftLibGhostContentControlsInContext(ctx) {
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
    if (!tag.startsWith(TAG_PREFIX)) continue;
    if (tag.startsWith(BIB_TAG_PREFIX)) continue;

    const text = rng.text || "";

    if (isBoundaryGuardTag(tag)) {
      if (text.trim() === "" || !text.includes(ZERO_WIDTH_SEPARATOR)) {
        cc.delete(false);
      }
      continue;
    }

    if (tag.startsWith(CITE_TAG_PREFIX)) {
      if (text.trim() === "") {
        if (typeof swiftLibTryDeleteLightweightGuardAfterCitationCC === "function") {
          await swiftLibTryDeleteLightweightGuardAfterCitationCC(ctx, cc);
        }
        cc.delete(false);
      }
    }
  }
  await ctx.sync();
}

async function cleanupSwiftLibGhostContentControls() {
  return Word.run(async (ctx) => {
    await deleteSwiftLibGhostContentControlsInContext(ctx);
  });
}

async function clearSwiftLibCitationCannotDeleteLocks() {
  try {
    await Word.run(async (ctx) => {
      const controls = ctx.document.contentControls;
      controls.load("items");
      await ctx.sync();
      for (const cc of controls.items) cc.load("tag");
      await ctx.sync();
      for (const cc of controls.items) {
        const t = cc.tag || "";
        if (!t.startsWith(TAG_PREFIX)) continue;
        tryClearCannotDelete(cc);
        const parsed = parseTag(t);
        if (!(parsed?.kind === "citation" && parsed.fromShortTag)) trySetPlaceholderEmpty(cc);
      }
      await ctx.sync();
    });
  } catch (e) {
    console.warn("clearSwiftLibCitationCannotDeleteLocks:", e);
  }
}

/**
 * Read collapsed selection typing format at the real insertion point (call before insertContentControl).
 * @returns {Promise<object|null>}
 */
async function captureFormatSnapshotAtCursor(ctx) {
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
    console.warn("SwiftLib captureFormatSnapshotAtCursor:", e);
    return null;
  }
}

/** Apply pre-captured cursor font to the guard character range, then caller sets hidden + tiny size. */
function applyFontSnapshotToGuardRange(guardRange, snap) {
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
    console.warn("SwiftLib applyFontSnapshotToGuardRange:", e);
  }
}

/**
 * Zero-width separator after citation CC (no extra content control). Hidden font where supported — fewer CCs / syncs.
 * @param {string} [citationIdForPendingFormat] — if set, consume pendingCitationGuardFormatById entry from pre-insert capture.
 */
async function insertLightweightGuardAfterCitationCC(ctx, citationCC, citationIdForPendingFormat) {
  const afterLoc = rangeLocationAfter();
  const afterRange = citationCC.getRange(afterLoc);
  const insStart =
    typeof Word !== "undefined" && Word.InsertLocation && Word.InsertLocation.start !== undefined
      ? Word.InsertLocation.start
      : "Start";
  afterRange.insertText(ZERO_WIDTH_SEPARATOR, insStart);
  await ctx.sync();
  let snap = null;
  if (citationIdForPendingFormat) {
    snap = pendingCitationGuardFormatById.get(citationIdForPendingFormat) || null;
    pendingCitationGuardFormatById.delete(citationIdForPendingFormat);
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
        applyFontSnapshotToGuardRange(guardRange, snap);
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
    console.warn("SwiftLib lightweight guard font:", e);
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

function rangeLocationAfter() {
  return typeof Word !== "undefined" && Word.RangeLocation && Word.RangeLocation.after !== undefined
    ? Word.RangeLocation.after
    : "After";
}

/**
 * After inserting a citation CC, Word may still leave the caret *inside* the control.
 * Call this after select(); sync — nudges the caret to immediately after the SwiftLib CC boundary.
 * Hop out of citation, bibliography, or boundary-guard CCs (caret lands after boundary guard when present).
 */
async function ensureCaretOutsideSwiftLibAnchors(ctx) {
  const afterLoc = rangeLocationAfter();
  for (let h = 0; h < 8; h++) {
    const parent = ctx.document.getSelection().parentContentControlOrNullObject;
    parent.load("tag");
    await ctx.sync();
    if (parent.isNullObject) return;
    const tag = parent.tag || "";
    const inside =
      tag.startsWith(CITE_TAG_PREFIX) ||
      tag.startsWith(BIB_TAG_PREFIX) ||
      isBoundaryGuardTag(tag);
    if (!inside) return;
    parent.getRange(afterLoc).select();
    await ctx.sync();
  }
}

/**
 * Walk up and exit any SwiftLib citation/bibliography content controls so the insertion
 * point is never nested (nested CC + replace refresh deletes inner citations).
 */
async function moveSelectionOutOfAllSwiftLibContentControls(ctx) {
  const maxHops = 32;
  const afterLoc = rangeLocationAfter();
  for (let h = 0; h < maxHops; h++) {
    const parentCC = ctx.document.getSelection().parentContentControlOrNullObject;
    parentCC.load("tag");
    await ctx.sync();
    if (parentCC.isNullObject) return;

    const tag = parentCC.tag || "";
    const inside =
      tag.startsWith(CITE_TAG_PREFIX) ||
      tag.startsWith(BIB_TAG_PREFIX) ||
      isBoundaryGuardTag(tag);
    if (!inside) return;

    parentCC.getRange(afterLoc).select();
    await ctx.sync();
  }
}

/**
 * Collapse multi-character selections so insertContentControl does not wrap a whole paragraph.
 * Then decide from the *live* document cursor whether we edit the surrounding citation or insert new.
 * (Stale state.editingCitationID from pane load is not reliable — task pane focus does not move the cursor.)
 */
async function resolveCitationInsertMode() {
  try {
    return await Word.run(async (ctx) => {
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
        } catch (e) {
          console.warn("collapse selection:", e);
        }
      }

      const parentCC = ctx.document.getSelection().parentContentControlOrNullObject;
      parentCC.load("tag");
      await ctx.sync();
      if (parentCC.isNullObject) return { mode: "new" };

      const tag = parentCC.tag || "";
      if (isBoundaryGuardTag(tag)) return { mode: "new" };
      if (!tag.startsWith(CITE_TAG_PREFIX)) return { mode: "new" };

      const parsed = parseCitationTag(tag);
      if (!parsed) return { mode: "new" };
      return { mode: "edit", citationId: parsed.id };
    });
  } catch (e) {
    console.warn("resolveCitationInsertMode:", e);
    return { mode: "new" };
  }
}

function generateUUID() {
  if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") {
    return crypto.randomUUID();
  }
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (ch) => {
    const rand = Math.floor(Math.random() * 16);
    const value = ch === "x" ? rand : ((rand & 0x3) | 0x8);
    return value.toString(16);
  });
}

// ---------------------------------------------------------------------------
// Document scan — read all SwiftLib content controls
// ---------------------------------------------------------------------------

function collectScanFromItems(items, snapMap) {
  const scan = SwiftLibShared.collectScanFromItems(items, snapMap, {
    tagPrefix: TAG_PREFIX,
    parseTag,
    readFallbackPayload: readCitationFallbackPayloadFromControl,
  });
  const citationIndexById = new Map(scan.citations.map((c) => [c.citationID, c]));
  const bibIndexById = new Map(scan.bibControls.map((b) => [b.ccId, b]));
  for (let i = 0; i < items.length; i++) {
    const cc = items[i];
    const citation = citationIndexById.get(cc.id);
    if (citation) {
      citation.index = i;
      citation.ccId = cc.id;
      continue;
    }
    const bib = bibIndexById.get(cc.id);
    if (bib) {
      bib.index = i;
      const parsed = parseTag(cc.tag || "");
      bib.bibliographyID = parsed?.id || "";
    }
  }
  return scan;
}

/** Detect if document gained/lost SwiftLib cites or bib blocks while an async gap left Word.run (e.g. insert during fetch). */
function scanStructuralSignature(scan) {
  const ids = scan.citations.map((c) => c.citationID).sort().join("|");
  return `${scan.bibControls.length}|${scan.citations.length}|${ids}`;
}

async function scanDocument() {
  return Word.run(async (ctx) => {
    const snapMap = await buildSnapshotCitationMap(ctx);
    const controls = ctx.document.contentControls;
    controls.load("items");
    await ctx.sync();

    const items = controls.items;
    if (!items.length) {
      tryTrackedObjectsRemoveAll(ctx);
      return { citations: [], bibControls: [] };
    }

    for (const cc of items) cc.load("tag,id,placeholderText");
    await ctx.sync();

    const scan = collectScanFromItems(items, snapMap);
    tryTrackedObjectsRemoveAll(ctx);
    return scan;
  });
}

// ---------------------------------------------------------------------------
// Collect all cited reference IDs from the document
// ---------------------------------------------------------------------------

async function refreshCitedIds() {
  try {
    const scan = await scanDocument();
    const ids = new Set();
    for (const c of scan.citations) {
      for (const id of c.ids) ids.add(id);
    }
    state.citedIds = ids;
  } catch (error) {
    console.warn("refreshCitedIds:", error);
  }
}

// ---------------------------------------------------------------------------
// Hydrate from selection — detect if cursor is inside an existing citation CC
// ---------------------------------------------------------------------------

/**
 * Restore the citation‐options panel fields (locator, prefix, suffix, suppress-author)
 * from one stored citationItem record (v4 schema, the first item in the array).
 */
function restoreCitationItemOptions(item) {
  const el = (id) => document.getElementById(id);
  if (!item) return;
  if (el("citOptLocator"))       el("citOptLocator").value         = item.locator          || "";
  if (el("citOptLocatorLabel"))  el("citOptLocatorLabel").value    = item.label            || "page";
  if (el("citOptPrefix"))        el("citOptPrefix").value          = item.prefix           || "";
  if (el("citOptSuffix"))        el("citOptSuffix").value          = item.suffix           || "";
  if (el("citOptSuppressAuthor")) el("citOptSuppressAuthor").checked = !!item["suppress-author"];
}

async function hydrateFromSelection() {
  try {
    const activeCitation = await Word.run(async (ctx) => {
      const selection = ctx.document.getSelection();
      const parentCC = selection.parentContentControlOrNullObject;
      parentCC.load("tag,id,placeholderText");
      await ctx.sync();

      if (parentCC.isNullObject) return null;

      const tag = parentCC.tag || "";
      if (isBoundaryGuardTag(tag)) return null;
      if (!tag.startsWith(CITE_TAG_PREFIX)) return null;

      const parsed = parseCitationTag(tag);
      if (!parsed) return null;
      const fallback = readCitationFallbackPayloadFromControl(parentCC);
      if ((parsed.fromShortTag || !parsed.ids?.length) && fallback?.ids?.length) {
        parsed.style = fallback.style || parsed.style || "";
        parsed.ids = fallback.ids.slice();
      }
      return parsed;
    });

    if (!activeCitation) {
      // Cursor is no longer inside any citation CC.
      // Auto-exit edit mode only if we entered it via cursor detection — don't
      // discard chips the user built manually via search.
      if (state.editEnteredBySelection) {
        cancelEditMode();
        // cancelEditMode clears editEnteredBySelection
      }
      updateSelectionUI();
      return;
    }

    // Cursor is still inside the SAME citation — don't re-hydrate so the user
    // can keep adding/removing chips without them being overwritten.
    if (state.editEnteredBySelection && state.editingCitationID === activeCitation.id) {
      updateSelectionUI();
      return;
    }

    state.editingCitationID = activeCitation.id;

    let resolvedIds = activeCitation.ids?.length ? activeCitation.ids.slice() : [];
    let resolvedStyle = activeCitation.style || "";
    let resolvedCitationItems = null; // v4: carries locator/prefix/suffix per item

    if (!resolvedIds.length) {
      const pend = state.pendingCitationPayload[activeCitation.id];
      if (pend?.ids?.length) {
        resolvedIds = pend.ids.slice();
        resolvedStyle = pend.style || resolvedStyle;
        resolvedCitationItems = pend.citationItems || null;
      } else if (isWordApi14()) {
        const row = await Word.run(async (ctx) => {
          const snap = await readSwiftLibStorage(ctx);
          tryTrackedObjectsRemoveAll(ctx);
          return (snap?.citations || []).find(
            (c) => String(c.citationId || "").toLowerCase() === activeCitation.id
          );
        });
        if (row) {
          // v4: citationItems carries full per-item options; fall back to legacy refIds
          if (row.citationItems?.length) {
            resolvedIds = row.citationItems.map((item) => {
              if (item.refId) return String(item.refId);
              if (item.itemRef?.startsWith("lib:")) return item.itemRef.slice(4);
              return null;
            }).filter(Boolean);
            resolvedCitationItems = row.citationItems;
          } else if (row.refIds?.length) {
            resolvedIds = row.refIds.map(String);
          }
          resolvedStyle = row.style || resolvedStyle;
        }
      }
    }

    state.preferredStyle = resolvedStyle || state.preferredStyle;
    const styleSelect = document.getElementById("styleSelect");
    if (styleSelect && styleSelect.options.length && state.preferredStyle) {
      styleSelect.value = state.preferredStyle;
    }

    if (resolvedIds.length) {
      const refs = await fetchJSON(`/api/references?ids=${resolvedIds.join(",")}`);

      // For items deleted from the library, fall back to the embedded snapshot
      // so we can still display something meaningful in the chips.
      let finalRefs = refs.slice();
      if (finalRefs.length < resolvedIds.length) {
        const foundIds = new Set(finalRefs.map((r) => String(r.id)));
        const snap = swiftLibStorageCache.payload?.items || {};
        for (const id of resolvedIds) {
          if (!foundIds.has(String(id))) {
            const si = snap[`lib:${id}`];
            if (si) {
              finalRefs.push({
                id: Number(id),
                title: si.title || `ID ${id}`,
                authors: (si.author || []).map((a) => a.family || a.literal || "").filter(Boolean).join(", "),
                year: si.issued?.["date-parts"]?.[0]?.[0] || null,
                _orphan: true,
              });
            }
          }
        }
        // Preserve original order
        const order = resolvedIds.map(String);
        finalRefs.sort((a, b) => order.indexOf(String(a.id)) - order.indexOf(String(b.id)));
      }

      setSelectedRefs(finalRefs);
      state.editEnteredBySelection = true;

      // Restore per-item citation options (locator, prefix, suffix…) from the snapshot
      if (resolvedCitationItems?.length) {
        restoreCitationItemOptions(resolvedCitationItems[0]);
      }

      const label = finalRefs.length
        ? `正在编辑：${finalRefs.slice(0, 3).map((r) => {
            const name = r.authors ? r.authors.split(",")[0].trim() : r.title;
            return name + (r.year ? ` (${r.year})` : "");
          }).join("；") + (finalRefs.length > 3 ? ` 等${finalRefs.length}条` : "")}`
        : "正在编辑引文";
      showEditBanner(label);
      setStatus("光标在引文中 — 可删除或追加文献，点击「更新引文」。");
    } else {
      // IDs could not be resolved at all (e.g. very old doc with no snapshot)
      state.editEnteredBySelection = true;
      showEditBanner("正在编辑引文");
      setStatus("光标在引文中，但未能解析文献条目。");
    }
  } catch (error) {
    console.warn("hydrateFromSelection:", error);
  }

  updateSelectionUI();
}

// ---------------------------------------------------------------------------
// Adjacent citation merge helper
// ---------------------------------------------------------------------------

/**
 * Check if the cursor is immediately adjacent to a previous citation CC
 * (inside or right after a boundary guard, or right after a citation CC).
 * Returns the citation CC to merge into, or null if not adjacent.
 */
async function findAdjacentCitationCC(ctx) {
  // Strategy: walk the content controls near the selection.
  // If the cursor is inside a boundary guard, the previous sibling CC should be a citation.
  // If the cursor is right after a citation CC (no text between), merge.
  const sel = ctx.document.getSelection();
  const parentCC = sel.parentContentControlOrNullObject;
  parentCC.load("tag");
  await ctx.sync();

  // Case 1: cursor is inside a boundary guard CC
  if (!parentCC.isNullObject && isBoundaryGuardTag(parentCC.tag || "")) {
    // The boundary guard is placed right after a citation CC.
    // We need to find the citation CC that precedes this guard.
    const controls = ctx.document.contentControls;
    controls.load("items");
    await ctx.sync();
    for (const cc of controls.items) cc.load("tag,id,placeholderText");
    await ctx.sync();

    // Find the boundary guard in the list, then look backward for citation CC
    let guardIdx = -1;
    for (let i = 0; i < controls.items.length; i++) {
      if (controls.items[i].id === parentCC.id) { guardIdx = i; break; }
    }
    if (guardIdx > 0) {
      for (let i = guardIdx - 1; i >= 0; i--) {
        const tag = controls.items[i].tag || "";
        if (tag.startsWith(CITE_TAG_PREFIX) && !isBoundaryGuardTag(tag)) {
          return controls.items[i];
        }
        // Skip other boundary guards
        if (isBoundaryGuardTag(tag)) continue;
        break;
      }
    }
    return null;
  }

  // Case 2: cursor is right after a boundary guard (not inside it)
  // Check if the character before cursor is a ZWSP boundary guard
  try {
    const selRange = sel.getRange();
    selRange.load("start");
    await ctx.sync();
    const cursorStart = selRange.start;
    if (typeof cursorStart !== "number" || cursorStart < 1) return null;

    // Scan all content controls and find the citation CC whose boundary guard ends right before cursor
    const controls = ctx.document.contentControls;
    controls.load("items");
    await ctx.sync();
    const pairs = [];
    for (const cc of controls.items) {
      cc.load("tag,id,placeholderText");
      const rng = cc.getRange();
      rng.load("start,end");
      pairs.push({ cc, rng });
    }
    await ctx.sync();

    // Sort by document position
    pairs.sort((a, b) => (a.rng.start ?? 0) - (b.rng.start ?? 0));

    // Find the last citation CC that ends right before (or at) the cursor position
    let lastCiteCC = null;
    let lastCiteEnd = -1;
    for (const { cc, rng } of pairs) {
      const tag = cc.tag || "";
      if (tag.startsWith(CITE_TAG_PREFIX) && !isBoundaryGuardTag(tag)) {
        lastCiteCC = cc;
        lastCiteEnd = rng.end ?? -1;
      }
      if (isBoundaryGuardTag(tag) && lastCiteCC) {
        // boundary guard is right after citation; its end is the effective end
        lastCiteEnd = rng.end ?? lastCiteEnd;
      }
      // If we've passed the cursor, stop
      if ((rng.start ?? 0) > cursorStart) break;
    }

    // Check adjacency: cursor should be within 2 chars of the last citation+guard end
    if (lastCiteCC && lastCiteEnd >= 0 && cursorStart <= lastCiteEnd + 2) {
      return lastCiteCC;
    }
  } catch (e) {
    console.warn("SwiftLib findAdjacentCitationCC range check:", e);
  }

  return null;
}

// ---------------------------------------------------------------------------
// Insert / edit citation — uses Content Control
// ---------------------------------------------------------------------------

async function upsertCitation() {
  if (upsertCitationBusy) return;

  // v4 Orphan/relink: if we're in relink mode, perform relink instead of normal insert
  if (state.relinkingOrphanId != null) {
    await performRelink();
    return;
  }

  const style = document.getElementById("styleSelect").value;
  const ids = state.selectedRefs.map((ref) => ref.id);

  // Fetch CSL snapshots for the selected refs so we can embed them in the document.
  // This makes the document self-contained and enables refresh without the local library.
  let cslSnapshots = {};
  try {
    const cslItems = await fetchJSON(`/api/cite-items?ids=${ids.join(",")}`);
    for (const item of cslItems) {
      const key = `lib:${item._swiftlibRefId || item.id}`;
      cslSnapshots[key] = item;
    }
  } catch (e) {
    console.warn("SwiftLib: failed to fetch CSL snapshots for upsert, continuing without:", e);
  }

  if (!ids.length) {
    setStatus("请至少选择一条文献。");
    return;
  }

  /** Snapshot so we can restore chips if Word insert fails after optimistic clear. */
  const selectionSnapshot = {
    refs: state.selectedRefs.slice(),
    ids: new Set(state.selectedIds),
  };

  upsertCitationBusy = true;
  runtimeLocks.upsertCitation = true;
  const primaryBtn = document.getElementById("primaryBtn");
  if (primaryBtn) primaryBtn.disabled = true;
  showLoadingOverlay("正在插入引文…");

  let citationID = "";
  try {
    clearCitationSelectionUI();

    setStatus("正在构建引文…");

    // Step 1: Merge insert-mode detection + CC insert into a single Word.run
    // (eliminates the separate resolveCitationInsertMode() Word.run)
    await Word.run(async (ctx) => {
      // --- Detect edit vs new mode inline ---
      const sel = ctx.document.getSelection();
      const selRange = sel.getRange();
      selRange.load("isCollapsed");
      const parentCC = sel.parentContentControlOrNullObject;
      parentCC.load("tag");
      await ctx.sync();

      if (selRange.isCollapsed === false) {
        try {
          if (Word.CollapseDirection && Word.CollapseDirection.end !== undefined) {
            selRange.collapse(Word.CollapseDirection.end);
            selRange.select();
            await ctx.sync();
          }
        } catch (_) { /* ignore */ }
      }

      let editingId = null;
      let editingCC = null;
      if (!parentCC.isNullObject) {
        const pTag = parentCC.tag || "";
        if (pTag.startsWith(CITE_TAG_PREFIX) && !isBoundaryGuardTag(pTag)) {
          const parsed = parseCitationTag(pTag);
          if (parsed) {
            editingId = parsed.id;
            editingCC = parentCC;
          }
        }
      }
      state.editingCitationID = editingId;

      citationID = editingId || generateUUID();
      const tagChoice = chooseCitationContentTag(citationID, style, ids);
      const tag = tagChoice.tag;
      // Build citationItems with full item options model, reading from the options panel
      const locator = document.getElementById("citOptLocator")?.value?.trim() || undefined;
      const locatorLabel = document.getElementById("citOptLocatorLabel")?.value || "page";
      const prefix = document.getElementById("citOptPrefix")?.value?.trim() || undefined;
      const suffix = document.getElementById("citOptSuffix")?.value?.trim() || undefined;
      const suppressAuthor = document.getElementById("citOptSuppressAuthor")?.checked || false;
      const citationItemsForPending = ids.map((id) => {
        const item = { itemRef: `lib:${id}`, refId: id };
        if (locator) { item.locator = locator; item.label = locatorLabel; }
        if (prefix) item.prefix = prefix;
        if (suffix) item["suffix"] = suffix;
        if (suppressAuthor) item["suppress-author"] = true;
        return item;
      });
      if (tagChoice.isShort) {
        state.pendingCitationPayload[citationID] = {
          style,
          ids: ids.slice(),
          citationItems: citationItemsForPending,
          itemSnapshots: cslSnapshots,
        };
      } else {
        delete state.pendingCitationPayload[citationID];
      }
      // Always store item snapshots in the cache so they survive even if tag is not short
      if (Object.keys(cslSnapshots).length) {
        if (!swiftLibStorageCache.payload) swiftLibStorageCache.payload = { v: 4, preferences: { style }, items: {}, citations: [], bibliography: false };
        if (!swiftLibStorageCache.payload.items) swiftLibStorageCache.payload.items = {};
        Object.assign(swiftLibStorageCache.payload.items, cslSnapshots);
        swiftLibStorageCache.lastJson = ""; // force re-persist
      }

      if (editingCC) {
        // --- Edit existing citation: update the parent CC directly ---
        editingCC.tag = tag;
        syncCitationFallbackPlaceholder(editingCC, { kind: "citation", fromShortTag: tagChoice.isShort }, style, ids);
        editingCC.insertText("[\u2026]", Word.InsertLocation.replace);
        try {
          await ctx.sync();
        } catch (e) {
          console.warn("SwiftLib: citation tag sync failed, using short tag", e);
          editingCC.tag = `${CITE_TAG_PREFIX}${citationID}`;
          state.pendingCitationPayload[citationID] = { style, ids: ids.slice() };
          syncCitationFallbackPlaceholder(editingCC, { kind: "citation", fromShortTag: true }, style, ids);
          editingCC.insertText("[\u2026]", Word.InsertLocation.replace);
          await ctx.sync();
        }
      } else {
        // --- Check if cursor is right after a boundary guard (adjacent to previous citation) ---
        let mergedIntoPrevious = false;
        try {
          const prevCC = await findAdjacentCitationCC(ctx);
          if (prevCC) {
            // Merge new ids into the previous citation CC
            const prevTag = prevCC.tag || "";
            const prevParsed = parseCitationTag(prevTag);
            let prevIds = prevParsed?.ids?.length ? prevParsed.ids.slice() : [];
            let prevStyle = prevParsed?.style || "";
            if (prevParsed?.fromShortTag || !prevIds.length) {
              const fb = readCitationFallbackPayloadFromControl(prevCC);
              if (fb?.ids?.length) { prevIds = fb.ids.slice(); prevStyle = fb.style || prevStyle; }
            }
            if (prevParsed?.fromShortTag && !prevIds.length) {
              const pend = state.pendingCitationPayload[prevParsed.id];
              if (pend?.ids?.length) { prevIds = pend.ids.slice(); prevStyle = pend.style || prevStyle; }
            }
            // Merge: add new ids that are not already present
            const mergedIds = prevIds.slice();
            for (const newId of ids) {
              if (!mergedIds.includes(newId)) mergedIds.push(newId);
            }
            const mergedCitationID = prevParsed?.id || citationID;
            citationID = mergedCitationID;
            const mergedTagChoice = chooseCitationContentTag(mergedCitationID, style, mergedIds);
            prevCC.tag = mergedTagChoice.tag;
            if (mergedTagChoice.isShort) {
              state.pendingCitationPayload[mergedCitationID] = { style, ids: mergedIds.slice() };
            } else {
              delete state.pendingCitationPayload[mergedCitationID];
            }
            syncCitationFallbackPlaceholder(prevCC, { kind: "citation", fromShortTag: mergedTagChoice.isShort }, style, mergedIds);
            prevCC.insertText("[\u2026]", Word.InsertLocation.replace);
            await ctx.sync();
            mergedIntoPrevious = true;
            console.log("SwiftLib: merged citation into adjacent CC", mergedCitationID, mergedIds);
          }
        } catch (mergeErr) {
          console.warn("SwiftLib: adjacent merge check failed, inserting new:", mergeErr);
        }

        if (!mergedIntoPrevious) {
          // --- Insert new citation ---
          await moveSelectionOutOfAllSwiftLibContentControls(ctx);
          const fmt = await captureFormatSnapshotAtCursor(ctx);
          if (fmt) pendingCitationGuardFormatById.set(citationID, fmt);
          const range = ctx.document.getSelection();
          const cc = range.insertContentControl("RichText");
          cc.title = CC_TITLE_CITE;
          cc.appearance = "Hidden";
          syncCitationFallbackPlaceholder(cc, { kind: "citation", fromShortTag: tagChoice.isShort }, style, ids);
          cc.tag = tag;
          try {
            await ctx.sync();
          } catch (e) {
            console.warn("SwiftLib: new citation tag sync failed, using short tag", e);
            cc.tag = `${CITE_TAG_PREFIX}${citationID}`;
            state.pendingCitationPayload[citationID] = { style, ids: ids.slice() };
            syncCitationFallbackPlaceholder(cc, { kind: "citation", fromShortTag: true }, style, ids);
            await ctx.sync();
          }
          cc.insertText("[\u2026]", Word.InsertLocation.replace);
          await ctx.sync();
          try {
            await insertLightweightGuardAfterCitationCC(ctx, cc, citationID);
          } catch (e) {
            console.warn("SwiftLib: lightweight guard skipped:", e);
          }
          try {
            await ensureCaretOutsideSwiftLibAnchors(ctx);
          } catch (e) {
            console.warn("SwiftLib: caret hop skipped:", e);
          }
          await ctx.sync();
        }
      }
    });

    setStatus("正在格式化引文…");

    const searchInput = document.getElementById("searchInput");
    if (searchInput) searchInput.value = "";
    state.lastQuery = "";
    clearSearchResultsPlaceholder();

    await yieldToPaint();

    await refreshDocument({ skipGhostCleanup: true, fromUpsert: true });
    clearCitationSelectionUI();
    setStatus("✓ 引文已插入。", "success");
    // Flash primary button green briefly
    const _primaryBtn = document.getElementById("primaryBtn");
    if (_primaryBtn) {
      _primaryBtn.classList.add("is-success");
      setTimeout(() => _primaryBtn.classList.remove("is-success"), 1400);
    }
    requestSearchFocus();
    if (!tryInsertMessageBox("引文已插入并完成格式化。")) {
      /* setStatus 已足够；无 messageBox 时不弹 alert 打扰 */
    }
  } catch (error) {
    console.error("SwiftLib upsertCitation:", error);
    pendingCitationGuardFormatById.delete(citationID);
    restoreCitationSelectionUI(selectionSnapshot.refs, selectionSnapshot.ids);
    setStatus(`引文插入失败：${error.message}`);
    const errMsg = `插入失败：${error.message || error}\n请检查后重试。`;
    if (!tryInsertMessageBox(errMsg)) {
      window.alert(errMsg);
    }
  } finally {
    hideLoadingOverlay();
    upsertCitationBusy = false;
    runtimeLocks.upsertCitation = false;
    updatePrimaryButton();
  }
}

// ---------------------------------------------------------------------------
// Refresh document — single Word.run: ghost cleanup → scan → fetch → reload CCs → (refetch if doc changed) → write → persist
// After await fetch, document may have changed (e.g. insert citation); reload itemsW before building rows / writing.
// ---------------------------------------------------------------------------

async function refreshDocument(options) {
  if (runtimeLocks.upsertCitation && !(options && options.fromUpsert === true)) {
    refreshDocumentQueued = true;
    return;
  }
  if (refreshDocumentBusy) {
    refreshDocumentQueued = true;
    return;
  }
  refreshDocumentBusy = true;
  try {
    let nextOpts = options;
    do {
      refreshDocumentQueued = false;
      await refreshDocumentOnce(nextOpts);
      nextOpts = undefined;
    } while (refreshDocumentQueued);
  } finally {
    refreshDocumentBusy = false;
  }
}

/**
 * @param {{ skipGhostCleanup?: boolean, fromUpsert?: boolean }} [options]
 *   skipGhostCleanup — post-insert: skip ghost CC pass (CustomXmlPart is still written when WordApi 1.4).
 */
async function refreshDocumentOnce(options) {
  const skipGhost = options && options.skipGhostCleanup === true;
  const trustInitialScan = options && options.fromUpsert === true;
  // Prefer document-persisted preferences.style over live UI state to prevent
  // UI state from polluting the document on every refresh.
  // Fall back to styleSelect.value only when no document preference is available.
  const snapStyle = swiftLibStorageCache.loaded
    ? (swiftLibStorageCache.payload?.preferences?.style || swiftLibStorageCache.payload?.style || null)
    : null;
  const style = snapStyle || document.getElementById("styleSelect").value;

  try {
    setStatus("正在刷新引文…");

    // Auto-save document before manual refresh to create a recovery point.
    // Skip for fromUpsert (single citation insert) to avoid latency.
    if (!trustInitialScan) {
      try {
        await Word.run(async (ctx) => { ctx.document.save(); await ctx.sync(); });
      } catch (saveErr) {
        console.warn("SwiftLib: pre-refresh save skipped:", saveErr);
      }
    }

    const result = await Word.run(async (ctx) => {
      if (!skipGhost) {
        await deleteSwiftLibGhostContentControlsInContext(ctx);
      }

      const snapMap = await buildSnapshotCitationMap(ctx);
      const controls = ctx.document.contentControls;
      controls.load("items");
      await ctx.sync();

      const items = controls.items;
      if (!items.length) {
        tryTrackedObjectsRemoveAll(ctx);
        return { kind: "empty" };
      }

      for (const cc of items) cc.load("tag,id,placeholderText");
      await ctx.sync();

      const scan = collectScanFromItems(items, snapMap);
      if (!scan.citations.length && !scan.bibControls.length) {
        tryTrackedObjectsRemoveAll(ctx);
        return { kind: "noSwiftLib" };
      }

      const data = await fetchDocumentRenderPayload(style, scan);
      if (data.error) {
        tryTrackedObjectsRemoveAll(ctx);
        return { kind: "error", message: data.error, orphanIds: data.orphanIds || [] };
      }

      // Step 2: fast path — for fromUpsert, trust the initial scan and skip
      // the expensive second CC reload + structural signature check.
      // The conservative double-check path is kept for manual Refresh / Repair.
      let finalItems = items;
      let finalScan = scan;
      let payload = data;

      if (!trustInitialScan) {
        // fetch 是异步间隙：此时另一个 Word.run 可能已插入新引文；必须重新 load 控件
        const ctrlFresh = ctx.document.contentControls;
        ctrlFresh.load("items");
        await ctx.sync();
        const itemsW = ctrlFresh.items;
        if (!itemsW.length) {
          tryTrackedObjectsRemoveAll(ctx);
          return { kind: "empty" };
        }
        for (const cc of itemsW) cc.load("tag,id,placeholderText");
        await ctx.sync();

        const scanW = collectScanFromItems(itemsW, snapMap);
        if (!scanW.citations.length && !scanW.bibControls.length) {
          tryTrackedObjectsRemoveAll(ctx);
          return { kind: "noSwiftLib" };
        }

        if (scanStructuralSignature(scan) !== scanStructuralSignature(scanW)) {
          payload = await fetchDocumentRenderPayload(style, scanW);
          if (payload.error) {
            tryTrackedObjectsRemoveAll(ctx);
            return { kind: "error", message: payload.error, orphanIds: payload.orphanIds || [] };
          }
        }
        finalItems = itemsW;
        finalScan = scanW;
      }

      const citationRows = [];
      const resolvedCitationMap = new Map(finalScan.citations.map((citation) => [citation.citationID, citation]));
      let primaryBibCC = null;
      const staleBibCCs = [];

      for (const cc of finalItems) {
        const parsed = parseTag(cc.tag);
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
        if (!t.startsWith(TAG_PREFIX)) continue;
        tryClearCannotDelete(cc);
        const parsed = parseTag(t);
        if (!(parsed?.kind === "citation" && parsed.fromShortTag)) trySetPlaceholderEmpty(cc);
      }

      const pendingCitationFormattingApplications = [];
      for (const row of citationRows) {
        const text = payload.citationTexts?.[row.parsed.id];
        if (text) {
          syncCitationFallbackPlaceholder(
            row.cc,
            row.parsed,
            row.resolved?.style || row.parsed.style || "",
            row.resolved?.ids || row.parsed.ids || []
          );
          const citationFormatting = citationFormattingForPayload(payload, row.parsed.id);
          const citationHtml =
            shouldInsertCitationAsHTML(citationFormatting)
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
        trySetPlaceholderEmpty(primaryBibCC);
        renderBibliographyIntoCC(primaryBibCC, payload.bibliographyText, payload.bibliographyHtml);
      }

      for (const stale of staleBibCCs) stale.delete(false);

      try {
        await persistSwiftLibStorageInContext(ctx, finalScan, style);
      } catch (persistErr) {
        console.warn("SwiftLib CustomXmlPart persist:", persistErr);
      }

      await ctx.sync();
      tryTrackedObjectsRemoveAll(ctx);
      return {
        kind: "ok",
        citationIDs: finalScan.citations.map((c) => c.citationID),
        orphanIds: payload.orphanIds || [],
        scan: finalScan,
      };
    });

    if (result.kind === "ok" && Array.isArray(result.citationIDs)) {
      for (const cid of result.citationIDs) delete state.pendingCitationPayload[cid];
    }

    if (result.kind === "empty" || result.kind === "noSwiftLib") {
      setStatus("文档中未找到 SwiftLib 引文。");
      updateOrphanBanner([]);
      await refreshCitedIds();
      renderResults(state.allResults);
      await refreshBibliographySummary();
      return;
    }
    if (result.kind === "error") {
      setStatus(`Refresh failed: ${result.message}`);
      // If the server identified orphan IDs (items deleted from library), show the
      // relink banner so the user can either relink to a new library item or clear them.
      if (result.orphanIds && result.orphanIds.length > 0) {
        updateOrphanBanner(result.orphanIds);
      }
      return;
    }

    // v4: show orphan banner if any citations were rendered from embedded snapshot
    updateOrphanBanner(result.orphanIds || []);

    // Use the scan data already collected during refresh to avoid redundant Word.run calls.
    if (result.scan) {
      const ids = new Set();
      for (const c of result.scan.citations) {
        for (const id of c.ids) ids.add(id);
      }
      state.citedIds = ids;
      state.citedCount = ids.size;
      state.hasBibliography = result.scan.bibControls.length > 0;

      renderResults(state.allResults);
      setStatus("引文已刷新。");

      const el = document.getElementById("docSummary");
      const parts = [];
      if (!ids.size) {
        parts.push("文档中尚无 SwiftLib 引文");
      } else {
        parts.push(`已引用 ${ids.size} 条不重复文献`);
        parts.push(state.hasBibliography ? "已含参考文献表" : "尚未插入参考文献表");
      }
      el.textContent = parts.join(" · ");
      updatePrimaryButton();
      updateInsertBibliographyButton();
    } else {
      await refreshCitedIds();
      renderResults(state.allResults);
      setStatus("引文已刷新。");
      await refreshBibliographySummary();
    }
  } catch (error) {
    setStatus(`Refresh failed: ${error.message}`);
  }
}

/**
 * v4 Orphan/relink: Perform relink — replace the orphan item's snapshot with the newly selected ref's CSL data.
 * Called when the user selects a replacement ref while in relink mode.
 */
async function performRelink() {
  const orphanId = state.relinkingOrphanId;
  if (orphanId == null) return;
  if (!state.selectedRefs.length) {
    setStatus("请选择一条文献作为 Relink 目标。");
    return;
  }

  const newRef = state.selectedRefs[0];
  const newId = newRef.id;

  try {
    setStatus("正在 Relink…");
    // Fetch CSL data for the new ref
    const cslItems = await fetchJSON(`/api/cite-items?ids=${newId}`);
    if (!cslItems || !cslItems.length) throw new Error("未能获取文献数据");
    const newCsl = cslItems[0];

    // Update the embedded items snapshot in CustomXmlPart:
    // 1. Replace the orphan key's CSL data with the new ref's CSL data
    // 2. Update all citation tags that referenced orphanId to reference newId
    await Word.run(async (ctx) => {
      const snap = await readSwiftLibStorage(ctx);
      if (!snap) throw new Error("未找到 SwiftLib 存储。");

      // Update items snapshot
      const orphanKey = `lib:${orphanId}`;
      const newKey = `lib:${newId}`;
      if (snap.items) {
        delete snap.items[orphanKey];
        // Store CSL JSON directly (same format as cslSnapshots in upsertCitation)
        snap.items[newKey] = newCsl;
      }

      // Update citations that referenced orphanId
      if (snap.citations) {
        for (const [citId, cit] of Object.entries(snap.citations)) {
          // v4 schema: citationItems (not cit.items)
          if (Array.isArray(cit.citationItems)) {
            cit.citationItems = cit.citationItems.map((item) =>
              item.itemRef === orphanKey ? { ...item, itemRef: newKey } : item
            );
          }
          // v4 schema: refIds (not cit.ids); also keep legacy ids for v3 compat
          if (Array.isArray(cit.refIds)) {
            cit.refIds = cit.refIds.map((id) => (id === orphanId ? newId : id));
          }
          if (Array.isArray(cit.ids)) {
            cit.ids = cit.ids.map((id) => (id === orphanId ? newId : id));
          }
        }
      }

      // Persist updated snapshot
      await persistSwiftLibStorageInContext(ctx, null, null, snap);
      await ctx.sync();
    });

    // Exit relink mode
    state.relinkingOrphanId = null;
    clearCitationSelectionUI();
    const editBanner = document.getElementById("editBanner");
    if (editBanner) editBanner.classList.add("hidden");

    // Refresh to re-render with the new ref
    setStatus("Relink 成功，正在刷新…");
    await refreshDocumentOnce();
  } catch (err) {
    console.error("SwiftLib relink:", err);
    setStatus(`Relink 失败：${err.message}`);
  }
}

/**
 * v4 Orphan/relink: Update the orphan banner in the taskpane.
 * orphanIds: array of Int64 IDs (numbers) that were rendered from embedded snapshot only.
 */
function updateOrphanBanner(orphanIds) {
  const banner = document.getElementById("orphanBanner");
  const list = document.getElementById("orphanBannerList");
  if (!banner || !list) return;

  if (!orphanIds || orphanIds.length === 0) {
    banner.classList.add("hidden");
    list.innerHTML = "";
    return;
  }

  list.innerHTML = "";
  for (const id of orphanIds) {
    // Try to find a label from the embedded snapshot in state
    // swiftLibStorageCache is a module-level variable (not on state);
    // items values are raw CSL JSON objects (no extra wrapper)
    const snapItem = swiftLibStorageCache.payload?.items?.[`lib:${id}`];
    const label = snapItem
      ? (snapItem.title || snapItem.author?.[0]?.family || `ID ${id}`)
      : `ID ${id}`;

    const li = document.createElement("li");
    const span = document.createElement("span");
    span.className = "orphan-item-label";
    span.textContent = label;
    span.title = label;

    const btn = document.createElement("button");
    btn.className = "orphan-relink-btn";
    btn.textContent = "Relink";
    btn.type = "button";
    btn.addEventListener("click", () => onRelinkOrphan(id, label));

    li.appendChild(span);
    li.appendChild(btn);
    list.appendChild(li);
  }

  banner.classList.remove("hidden");
}

/**
 * v4 Orphan/relink: Handle relink button click.
 * Opens the search area pre-filled with the orphan item's title for the user to select a replacement.
 */
function onRelinkOrphan(orphanId, label) {
  // Store the orphan ID being relinked so we can update the snapshot on confirm
  state.relinkingOrphanId = orphanId;

  // Pre-fill search with the orphan item's title to help user find the replacement
  const searchInput = document.getElementById("searchInput");
  if (searchInput) {
    searchInput.value = label;
    searchInput.dispatchEvent(new Event("input", { bubbles: true }));
    searchInput.focus();
  }

  // Show a banner indicating relink mode
  const editBanner = document.getElementById("editBanner");
  const editBannerText = document.getElementById("editBannerText");
  if (editBanner && editBannerText) {
    editBannerText.textContent = `正在 Relink：${label}`;
    editBanner.classList.remove("hidden");
  }
}

function renderBibliographyIntoCC(cc, bibliographyText, bibliographyHtml) {
  // Always use plain-text paragraph insertion so we can force Word.Style.normal
  // on every entry, regardless of the cursor's surrounding heading style.
  // (insertHtml is intentionally avoided: it inherits the ambient paragraph style
  //  and carries citeproc-js wrapper divs that Word renders unpredictably.)
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



// ---------------------------------------------------------------------------
// Document summary (citations / bibliography block)
// ---------------------------------------------------------------------------

async function refreshBibliographySummary() {
  try {
    // Use lightweight scanDocument (single Word.run) for routine UI updates.
    // reconcileDocument (which reads CustomXmlPart) is only called by repairAndRefresh.
    const scan = await scanDocument();

    const uniqueIds = new Set();
    for (const c of scan.citations) {
      for (const id of c.ids) uniqueIds.add(id);
    }

    state.citedCount = uniqueIds.size;
    state.hasBibliography = scan.bibControls.length > 0;

    const el = document.getElementById("docSummary");
    const parts = [];
    if (!uniqueIds.size) {
      parts.push("文档中尚无 SwiftLib 引文");
    } else {
      parts.push(`已引用 ${uniqueIds.size} 条不重复文献`);
      parts.push(state.hasBibliography ? "已含参考文献表" : "尚未插入参考文献表");
    }
    el.textContent = parts.join(" · ");
  } catch (error) {
    document.getElementById("docSummary").textContent = `无法读取文档：${error.message}`;
  }

  updatePrimaryButton();
  updateInsertBibliographyButton();
}

// ---------------------------------------------------------------------------
// Repair: delete broken CCs then full refresh
// ---------------------------------------------------------------------------

async function repairAndRefresh() {
  try {
    swiftLibStorageCache.loaded = false;
    swiftLibStorageCache.payload = null;
    swiftLibStorageCache.lastJson = "";
    setStatus("正在扫描异常标签…");
    const recon = await reconcileDocument();
    const brokenCount = recon.broken.length;

    if (brokenCount) {
      await Word.run(async (ctx) => {
        const controls = ctx.document.contentControls;
        controls.load("items");
        await ctx.sync();
        for (const cc of controls.items) cc.load("tag,id");
        await ctx.sync();

        const brokenIds = new Set(recon.broken.map((cc) => cc.id));
        for (const cc of controls.items) {
          if (brokenIds.has(cc.id)) cc.delete(false);
        }
        await ctx.sync();
        tryTrackedObjectsRemoveAll(ctx);
      });
      setStatus(`Removed ${brokenCount} broken CC${brokenCount === 1 ? "" : "s"}. Refreshing…`);
    }

    await refreshDocument();
    if (brokenCount) {
      setStatus(`Repaired ${brokenCount} broken tag${brokenCount === 1 ? "" : "s"} and refreshed.`);
    }
  } catch (error) {
    setStatus(`Repair failed: ${error.message}`);
  }
}

// ---------------------------------------------------------------------------
// Search & selection
// ---------------------------------------------------------------------------

async function search(query) {
  state.lastQuery = query;
  const trimmed = query.trim();
  if (!trimmed) {
    clearSearchResultsPlaceholder();
    if (state.shouldRefocusSearch) focusSearchInput();
    return;
  }

  try {
    const startedAt = performance.now();
    const refs = await fetchJSON(`/api/search?q=${encodeURIComponent(trimmed)}&limit=30`);
    state.allResults = refs;
    state.activeResultIndex = refs.length ? 0 : -1;
    renderResults(refs);

    const elapsed = Math.round(performance.now() - startedAt);
    const suffix = ` for "${trimmed}"`;
    setStatus(`${refs.length} result${refs.length === 1 ? "" : "s"}${suffix} (${elapsed}ms)`);
  } catch (error) {
    setStatus(`Cannot connect to SwiftLib: ${error.message}`);
    renderEmpty("无法连接 SwiftLib。");
  }

  if (state.shouldRefocusSearch) focusSearchInput();
}

const REF_TYPE_LABELS = {
  journalArticle: "期刊",
  book: "书籍",
  bookSection: "章节",
  conferencePaper: "会议",
  thesis: "学位论文",
  webpage: "网页",
  report: "报告",
  patent: "专利",
  other: "其他",
};

function renderResults(refs) {
  if (!refs.length) {
    renderEmpty("未找到文献。");
    return;
  }

  // Hide recent label when showing search results
  const recentLabel = document.getElementById("recentLabel");
  if (recentLabel && state.lastQuery.trim()) recentLabel.style.display = "none";

  const html = refs
    .map((ref, index) => {
      const selected = state.selectedIds.has(ref.id);
      const active = index === state.activeResultIndex;
      const cited = state.citedIds.has(ref.id);
      const year = ref.year ? ` (${ref.year})` : "";
      const journal = ref.journal ? `<br><em>${escapeHtml(ref.journal)}</em>` : "";
      const citedBadge = cited ? `<span class="cited-badge">已引用</span><span class="managed-badge">已管理</span>` : "";
      const typeBadge = ref.referenceType && REF_TYPE_LABELS[ref.referenceType]
        ? `<span class="ref-type-badge">${REF_TYPE_LABELS[ref.referenceType]}</span>`
        : "";
      const checkMark = selected ? `<span class="ref-item-check" aria-label="已选中">✓</span>` : "";
      return `
        <div class="ref-item ${selected ? "selected" : ""} ${active ? "active" : ""} ${cited ? "ref-cited" : ""}" data-id="${ref.id}" style="display:flex;align-items:flex-start;gap:8px;">
          <div style="flex:1;min-width:0;">
            <div class="ref-title">${typeBadge}${escapeHtml(ref.title)}${citedBadge}</div>
            <div class="ref-meta">${escapeHtml(ref.authors)}${year}${journal}</div>
          </div>
          ${checkMark}
        </div>
      `;
    })
    .join("");

  const container = document.getElementById("results");
  container.innerHTML = html;

  for (const el of container.querySelectorAll(".ref-item")) {
    const id = Number(el.dataset.id);
    el.addEventListener("click", () => addSelectionById(id));
    el.addEventListener("dblclick", () => quickInsertById(id));
  }

  scrollActiveResultIntoView();
  updatePrimaryButton();
}

function renderEmpty(message) {
  let detail = "试试标题、作者、期刊或年份关键词。";
  if ((message || "").includes("无法连接")) {
    detail = "请确认 SwiftLib 桌面端正在运行，然后重新刷新。";
  } else if ((message || "").includes("未找到")) {
    detail = "换个更短的关键词，或者试试作者姓氏与年份。";
  }
  document.getElementById("results").innerHTML = `
    <div class="empty">
      <div class="empty-title">${escapeHtml(message)}</div>
      <div class="empty-copy">${escapeHtml(detail)}</div>
    </div>
  `;
  updatePrimaryButton();
}

function moveActiveResult(step) {
  if (!state.allResults.length) return;
  const next = state.activeResultIndex < 0
    ? 0
    : (state.activeResultIndex + step + state.allResults.length) % state.allResults.length;
  state.activeResultIndex = next;
  renderResults(state.allResults);
}

function addActiveResult() {
  if (!state.allResults.length || state.activeResultIndex < 0) return;
  addSelection(state.allResults[state.activeResultIndex]);
}

function addSelectionById(id) {
  const ref = state.allResults.find((r) => r.id === id);
  if (ref) addSelection(ref);
}

function addSelection(ref) {
  if (state.selectedIds.has(ref.id)) {
    setStatus("该文献已添加。");
    requestSearchFocus();
    return;
  }

  state.selectedIds.add(ref.id);
  state.selectedRefs.push(ref);
  document.getElementById("searchInput").value = "";
  state.lastQuery = "";
  state.shouldRefocusSearch = true;
  updateSelectionUI();
  clearSearchResultsPlaceholder();
  requestSearchFocus();
}

async function quickInsertById(id) {
  const ref = state.allResults.find((r) => r.id === id);
  if (!ref) return;
  if (!state.selectedIds.has(ref.id)) addSelection(ref);
  await upsertCitation();
}

function setSelectedRefs(refs) {
  state.selectedRefs = refs.slice();
  state.selectedIds = new Set(refs.map((r) => r.id));
  updateSelectionUI();
}

function removeSelectedId(id) {
  state.selectedIds.delete(id);
  state.selectedRefs = state.selectedRefs.filter((r) => r.id !== id);
  state.shouldRefocusSearch = true;
  updateSelectionUI();
  requestSearchFocus();
}

function updateSelectionUI() {
  const tokens = document.getElementById("selectionTokens");
  if (!tokens) return;

  const optPanel = document.getElementById("citationOptionsPanel");
  const multiHint = document.getElementById("citOptMultiHint");

  if (!state.selectedRefs.length) {
    tokens.replaceChildren();
    // Hide the <details> options panel entirely when nothing is selected
    if (optPanel) optPanel.style.display = "none";
    updatePrimaryButton();
    return;
  }

  tokens.innerHTML = state.selectedRefs.map(renderSelectedToken).join("");
  for (const el of tokens.querySelectorAll(".chip-remove")) {
    el.addEventListener("click", () => removeSelectedId(Number(el.dataset.id)));
  }
  // Show citation options <details> panel when at least one ref is selected
  if (optPanel) optPanel.style.display = "";
  // Show multi-item hint only when multiple refs are selected
  if (multiHint) {
    multiHint.classList.toggle("visible", state.selectedRefs.length > 1);
  }
  updatePrimaryButton();
}

function renderSelectedToken(ref, index) {
  const year = ref.year ? ` (${ref.year})` : "";
  const label = ref.authors ? `${escapeHtml(ref.authors)}${year}` : `${escapeHtml(ref.title)}${year}`;
  return `
    <div class="chip" title="${escapeHtml(ref.title)}">
      <span class="chip-index">${index + 1}</span>
      <div class="chip-text">${label}</div>
      <button class="chip-remove" type="button" data-id="${ref.id}" aria-label="移除">×</button>
    </div>
  `;
}

function scrollActiveResultIntoView() {
  const active = document.querySelector(".ref-item.active");
  if (active) active.scrollIntoView({ block: "nearest" });
}

function updatePrimaryButton() {
  const button = document.getElementById("primaryBtn");
  if (!button) return;
  const n = state.selectedRefs.length;
  button.textContent = n > 0 ? `插入引文${n > 1 ? ` (${n})` : ""}` : "插入引文";
  button.disabled = n === 0;
  // Remove success animation class when button state changes
  button.classList.remove("is-success");
}

function updateInsertBibliographyButton() {
  const btn = document.getElementById("insertBibBtn");
  if (!btn) return;
  btn.disabled = state.citedCount === 0;
}

async function insertBibliographyFromTaskpane() {
  if (insertBibliographyFromTaskpaneBusy) return;
  if (typeof swiftLibPerformInsertBibliography !== "function") {
    setStatus("参考文献功能未就绪，请重新加载加载项。");
    return;
  }
  insertBibliographyFromTaskpaneBusy = true;
  showLoadingOverlay("正在插入参考文献表…");
  try {
    const result = await swiftLibPerformInsertBibliography();
    if (!result.ok) {
      if (result.code === "no_citations") {
        setStatus("文档中还没有 SwiftLib 引文，请先插入引文。");
        if (!tryInsertMessageBox("文档中还没有引文，请先使用「插入引文」。")) {
          window.alert("文档中还没有引文，请先使用「插入引文」。");
        }
      } else {
        const msg = result.message || "未知错误";
        setStatus(`参考文献表失败：${msg}`);
        if (!tryInsertMessageBox(`参考文献表失败：${msg}`)) {
          window.alert(`参考文献表失败：${msg}`);
        }
      }
      return;
    }
    setStatus("参考文献表已插入或更新。");
    await refreshBibliographySummary();
  } catch (e) {
    console.error("insertBibliographyFromTaskpane:", e);
    setStatus(`参考文献表失败：${e.message || e}`);
  } finally {
    hideLoadingOverlay();
    insertBibliographyFromTaskpaneBusy = false;
  }
}

async function runPrimaryAction() {
  await upsertCitation();
}

// ---------------------------------------------------------------------------
// Utilities
// ---------------------------------------------------------------------------

async function fetchJSON(pathOrUrl, options) {
  const opts = options ? { ...options } : {};
  opts.headers = Object.assign({}, opts.headers || {});
  if (window.__SWIFTLIB_TOKEN) opts.headers["Authorization"] = "Bearer " + window.__SWIFTLIB_TOKEN;
  const response = await fetch(pathOrUrl, opts);
  if (!response.ok) {
    const fallback = await response.text();
    let message = fallback || `HTTP ${response.status}`;
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
  return response.json();
}

function setStatus(message, type) {
  const el = document.getElementById("status");
  if (!el) return;
  el.textContent = message;
  el.className = "status-bar" + (type ? ` is-${type}` : "");
  // Auto-clear success styling after 3s
  if (type === "success") {
    setTimeout(() => {
      if (el.textContent === message) el.className = "status-bar";
    }, 3000);
  }
}

function requestSearchFocus() {
  state.shouldRefocusSearch = true;
  focusSearchInput({ preservePending: true });
}

function focusSearchInput(options = {}) {
  window.setTimeout(() => {
    const input = document.getElementById("searchInput");
    if (!input) return;
    input.focus();
    const caret = input.value.length;
    input.setSelectionRange(caret, caret);
    if (!options.preservePending) state.shouldRefocusSearch = false;
  }, 0);
}

function escapeHtml(value) {
  const el = document.createElement("div");
  el.textContent = value ?? "";
  return el.innerHTML;
}

// ===========================================================================
// Style Manager — CSL import, Zotero repository search, custom style delete
// ===========================================================================

// ---------------------------------------------------------------------------
// Toggle style manager drawer
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Toggle citation marks visibility in document
// ---------------------------------------------------------------------------

let citationMarksVisible = false;

/**
 * Toggle the appearance of all SwiftLib citation Content Controls between
 * "BoundingBox" (visible — user can see which [1] are managed) and
 * "Hidden" (invisible — clean document view).
 *
 * When BoundingBox is shown, the CC displays a subtle colored border around
 * the citation text, making it visually distinct from hand-typed text.
 */
async function toggleCitationMarks() {
  citationMarksVisible = !citationMarksVisible;
  const newAppearance = citationMarksVisible ? "BoundingBox" : "Hidden";

  // Update button label
  const btn = document.getElementById("toggleCiteMarksBtn");
  if (btn) btn.textContent = citationMarksVisible ? "\u2713 \u663e\u793a\u5f15\u7528\u6807\u8bb0" : "\u663e\u793a\u5f15\u7528\u6807\u8bb0";

  try {
    await Word.run(async (ctx) => {
      const controls = ctx.document.contentControls;
      controls.load("items");
      await ctx.sync();

      for (const cc of controls.items) {
        cc.load("tag,title");
      }
      await ctx.sync();

      for (const cc of controls.items) {
        const tag = cc.tag || "";
        const title = cc.title || "";
        // Only toggle citation CCs (not bibliography, not boundary guards)
        if (tag.startsWith(CITE_TAG_PREFIX) && !isBoundaryGuardTag(tag)) {
          cc.appearance = newAppearance;
          if (citationMarksVisible) {
            // Set a recognizable color for the bounding box
            try { cc.color = "#0f6cbd"; } catch (_) {}
          }
        }
        // Also toggle bibliography CC
        if (tag.startsWith(BIB_TAG_PREFIX)) {
          cc.appearance = newAppearance;
          if (citationMarksVisible) {
            try { cc.color = "#166b43"; } catch (_) {}
          }
        }
      }
      await ctx.sync();
    });
    setStatus(citationMarksVisible ? "\u5f15\u7528\u6807\u8bb0\u5df2\u663e\u793a\u3002\u84dd\u8272\u6846 = \u5f15\u6587\uff0c\u7eff\u8272\u6846 = \u53c2\u8003\u6587\u732e\u8868" : "\u5f15\u7528\u6807\u8bb0\u5df2\u9690\u85cf\u3002");
  } catch (error) {
    console.error("SwiftLib toggleCitationMarks:", error);
    setStatus(`\u5207\u6362\u5931\u8d25\uff1a${error.message}`);
  }
}

// ---------------------------------------------------------------------------
// Style Manager
// ---------------------------------------------------------------------------

function initStyleManager() {
  const manageBtn = document.getElementById("styleManageBtn");
  const manager   = document.getElementById("styleManager");
  if (!manageBtn || !manager) return;

  manageBtn.addEventListener("click", () => {
    const isOpen = manager.classList.toggle("is-open");
    manageBtn.classList.toggle("active", isOpen);
    if (isOpen) {
      refreshCustomStylesList();
      document.getElementById("zoteroResults").innerHTML = "";
      document.getElementById("zoteroSearchInput").value = "";
      setStyleManagerStatus("");
    }
  });

  // Close drawer when clicking outside
  document.addEventListener("click", (e) => {
    if (!manager.contains(e.target) && !manageBtn.contains(e.target)) {
      manager.classList.remove("is-open");
      manageBtn.classList.remove("active");
    }
  });

  // File drop zone
  const dropZone  = document.getElementById("styleDropZone");
  const fileInput = document.getElementById("styleFileInput");

  dropZone.addEventListener("click", () => fileInput.click());
  dropZone.addEventListener("keydown", (e) => { if (e.key === "Enter" || e.key === " ") fileInput.click(); });

  dropZone.addEventListener("dragover", (e) => { e.preventDefault(); dropZone.classList.add("drag-over"); });
  dropZone.addEventListener("dragleave", () => dropZone.classList.remove("drag-over"));
  dropZone.addEventListener("drop", (e) => {
    e.preventDefault();
    dropZone.classList.remove("drag-over");
    const files = Array.from(e.dataTransfer.files).filter(f => f.name.endsWith(".csl") || f.name.endsWith(".xml"));
    if (files.length) importLocalCSLFiles(files);
  });

  fileInput.addEventListener("change", () => {
    const files = Array.from(fileInput.files);
    if (files.length) importLocalCSLFiles(files);
    fileInput.value = "";
  });

  // Zotero search
  const zoteroSearchBtn   = document.getElementById("zoteroSearchBtn");
  const zoteroSearchInput = document.getElementById("zoteroSearchInput");

  zoteroSearchBtn.addEventListener("click", () => runZoteroSearch());
  zoteroSearchInput.addEventListener("keydown", (e) => { if (e.key === "Enter") runZoteroSearch(); });
}

// ---------------------------------------------------------------------------
// Status helper
// ---------------------------------------------------------------------------

function setStyleManagerStatus(msg, type) {
  const el = document.getElementById("styleManagerStatus");
  if (!el) return;
  el.textContent = msg || "";
  el.className = "style-manager-status" + (type ? ` ${type}` : "");
}

// ---------------------------------------------------------------------------
// Import local CSL files via POST /api/styles/import
// ---------------------------------------------------------------------------

async function importLocalCSLFiles(files) {
  setStyleManagerStatus("正在导入…");
  let successCount = 0;
  let errors = [];

  for (const file of files) {
    try {
      const xml = await file.text();
      // Parse title and id from CSL XML
      const { id: styleId, title: styleTitle } = extractCSLMeta(xml);
      if (!styleId) {
        errors.push(`${file.name}: 无法读取样式 ID`);
        continue;
      }

      await fetchJSON("/api/styles/import", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ id: styleId, title: styleTitle || file.name.replace(/\.csl$/i, ""), xml }),
      });
      successCount++;
    } catch (e) {
      errors.push(`${file.name}: ${e.message}`);
    }
  }

  if (errors.length) {
    setStyleManagerStatus(`导入失败：${errors.join("; ")}`, "error");
  } else {
    setStyleManagerStatus(`成功导入 ${successCount} 个样式`, "ok");
  }

  await loadStyles();
  refreshCustomStylesList();
}

// ---------------------------------------------------------------------------
// Extract id and title from CSL XML string (lightweight, no full parse)
// ---------------------------------------------------------------------------

function extractCSLMeta(xml) {
  const idMatch    = xml.match(/<id[^>]*>([^<]+)<\/id>/i);
  const titleMatch = xml.match(/<title[^>]*>([^<]+)<\/title>/i);

  let id = (idMatch ? idMatch[1].trim() : "").replace(/^https?:\/\/www\.zotero\.org\/styles\//, "");
  const title = titleMatch ? titleMatch[1].trim() : "";

  // Fallback: use last path segment of URL-style id
  if (!id && idMatch) {
    const parts = idMatch[1].trim().split("/");
    id = parts[parts.length - 1] || "";
  }

  return { id, title };
}

// ---------------------------------------------------------------------------
// Zotero CSL repository search (via GitHub API / Zotero CDN)
// ---------------------------------------------------------------------------

const ZOTERO_REPO_API = "https://api.github.com/search/code?q={query}+repo:citation-style-language/styles+extension:csl&per_page=10";
const ZOTERO_CDN_BASE = "https://raw.githubusercontent.com/citation-style-language/styles/master/";

// Simple in-memory cache for Zotero search results
const zoteroSearchCache = {};

async function runZoteroSearch() {
  const input = document.getElementById("zoteroSearchInput");
  const query = (input ? input.value : "").trim();
  if (!query) return;

  const btn = document.getElementById("zoteroSearchBtn");
  if (btn) btn.disabled = true;
  setStyleManagerStatus("正在搜索 Zotero 样式仓库…");
  document.getElementById("zoteroResults").innerHTML = "";

  try {
    const results = await searchZoteroStyles(query);
    renderZoteroResults(results);
    setStyleManagerStatus(results.length ? `找到 ${results.length} 个样式` : "未找到匹配样式，换个关键词试试");
  } catch (e) {
    setStyleManagerStatus(`搜索失败：${e.message}`, "error");
  } finally {
    if (btn) btn.disabled = false;
  }
}

/**
 * Search Zotero CSL styles.
 * Strategy: use GitHub Search API (no auth needed for low-rate usage),
 * then fall back to a curated popular-styles list if the API is rate-limited.
 */
async function searchZoteroStyles(query) {
  if (zoteroSearchCache[query]) return zoteroSearchCache[query];

  const q = encodeURIComponent(query);
  const url = `https://api.github.com/search/code?q=${q}+repo:citation-style-language/styles+extension:csl&per_page=12`;

  let results = [];

  try {
    const resp = await fetch(url, {
      headers: { "Accept": "application/vnd.github+json" }
    });

    if (resp.status === 403 || resp.status === 429) {
      // Rate limited — fall back to built-in popular list
      results = filterPopularStyles(query);
    } else if (resp.ok) {
      const data = await resp.json();
      results = (data.items || []).map(item => {
        const stem = item.name.replace(/\.csl$/i, "");
        return {
          id: stem,
          title: formatStyleTitle(stem),
          filename: item.name,
          url: `${ZOTERO_CDN_BASE}${item.name}`,
        };
      });
    } else {
      results = filterPopularStyles(query);
    }
  } catch (_) {
    results = filterPopularStyles(query);
  }

  zoteroSearchCache[query] = results;
  return results;
}

/** Format a CSL filename stem into a readable title */
function formatStyleTitle(stem) {
  return stem
    .replace(/-/g, " ")
    .replace(/\b\w/g, c => c.toUpperCase());
}

/** Built-in curated list for offline / rate-limited fallback */
const POPULAR_STYLES = [
  { id: "apa",                          title: "APA 7th Edition",                    filename: "apa.csl" },
  { id: "apa-6th-edition",              title: "APA 6th Edition",                    filename: "apa-6th-edition.csl" },
  { id: "mla",                          title: "MLA 9th Edition",                    filename: "modern-language-association.csl" },
  { id: "modern-language-association",  title: "Modern Language Association (MLA)",  filename: "modern-language-association.csl" },
  { id: "chicago-author-date",          title: "Chicago Author-Date",                filename: "chicago-author-date.csl" },
  { id: "chicago-note-bibliography",    title: "Chicago Note-Bibliography",          filename: "chicago-note-bibliography.csl" },
  { id: "ieee",                         title: "IEEE",                               filename: "ieee.csl" },
  { id: "harvard-cite-them-right",      title: "Harvard (Cite Them Right)",          filename: "harvard-cite-them-right.csl" },
  { id: "vancouver",                    title: "Vancouver",                          filename: "vancouver.csl" },
  { id: "nature",                       title: "Nature",                             filename: "nature.csl" },
  { id: "science",                      title: "Science",                            filename: "science.csl" },
  { id: "cell",                         title: "Cell",                               filename: "cell.csl" },
  { id: "the-lancet",                   title: "The Lancet",                         filename: "the-lancet.csl" },
  { id: "nejm",                         title: "New England Journal of Medicine",    filename: "new-england-journal-of-medicine.csl" },
  { id: "new-england-journal-of-medicine", title: "New England Journal of Medicine", filename: "new-england-journal-of-medicine.csl" },
  { id: "elsevier-harvard",             title: "Elsevier Harvard",                   filename: "elsevier-harvard.csl" },
  { id: "elsevier-vancouver",           title: "Elsevier Vancouver",                 filename: "elsevier-vancouver.csl" },
  { id: "springer-basic-author-date",   title: "Springer Basic Author-Date",         filename: "springer-basic-author-date.csl" },
  { id: "gb-t-7714-2015-numeric",       title: "GB/T 7714-2015 (顺序编码)",          filename: "gb-t-7714-2015-numeric.csl" },
  { id: "gb-t-7714-2015-author-date",   title: "GB/T 7714-2015 (著者-出版年)",       filename: "gb-t-7714-2015-author-date.csl" },
  { id: "gb-t-7714-2005",               title: "GB/T 7714-2005",                     filename: "gb-t-7714-2005.csl" },
  { id: "turabian-fullnote-bibliography", title: "Turabian Full Note",               filename: "turabian-fullnote-bibliography.csl" },
  { id: "bluebook-law-review",          title: "Bluebook Law Review",                filename: "bluebook-law-review.csl" },
  { id: "american-medical-association", title: "American Medical Association (AMA)", filename: "american-medical-association.csl" },
  { id: "american-chemical-society",    title: "American Chemical Society (ACS)",    filename: "american-chemical-society.csl" },
  { id: "american-political-science-association", title: "APSA",                     filename: "american-political-science-association.csl" },
  { id: "american-sociological-association",      title: "ASA",                      filename: "american-sociological-association.csl" },
  { id: "plos-one",                     title: "PLOS ONE",                           filename: "plos-one.csl" },
  { id: "frontiers",                    title: "Frontiers Journals",                 filename: "frontiers.csl" },
  { id: "biomed-central",               title: "BioMed Central",                     filename: "biomed-central.csl" },
];

function filterPopularStyles(query) {
  const q = query.toLowerCase();
  return POPULAR_STYLES.filter(s =>
    s.title.toLowerCase().includes(q) || s.id.toLowerCase().includes(q)
  ).map(s => ({
    ...s,
    url: `${ZOTERO_CDN_BASE}${s.filename}`,
  }));
}

// ---------------------------------------------------------------------------
// Render Zotero search results
// ---------------------------------------------------------------------------

function renderZoteroResults(results) {
  const container = document.getElementById("zoteroResults");
  if (!container) return;

  if (!results.length) {
    container.innerHTML = `<div class="custom-styles-empty">未找到匹配样式</div>`;
    return;
  }

  container.innerHTML = results.map(r => `
    <div class="zotero-result-item">
      <span class="zotero-result-name" title="${escapeHtml(r.id)}">${escapeHtml(r.title)}</span>
      <button class="btn-sm btn-sm-primary" data-url="${escapeHtml(r.url)}" data-id="${escapeHtml(r.id)}" data-title="${escapeHtml(r.title)}" type="button">安装</button>
    </div>
  `).join("");

  for (const btn of container.querySelectorAll("button[data-url]")) {
    btn.addEventListener("click", async () => {
      const url   = btn.dataset.url;
      const id    = btn.dataset.id;
      const title = btn.dataset.title;
      btn.disabled = true;
      btn.textContent = "安装中…";
      await installZoteroStyle(url, id, title);
      btn.textContent = "已安装";
    });
  }
}

// ---------------------------------------------------------------------------
// Download and install a Zotero CSL style from CDN
// ---------------------------------------------------------------------------

async function installZoteroStyle(url, id, title) {
  setStyleManagerStatus("正在下载样式…");
  try {
    const resp = await fetch(url);
    if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
    const xml = await resp.text();

    // Re-extract meta from actual file (may differ from search result)
    const meta = extractCSLMeta(xml);
    const finalId    = meta.id    || id;
    const finalTitle = meta.title || title;

    await fetchJSON("/api/styles/import", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ id: finalId, title: finalTitle, xml }),
    });

    setStyleManagerStatus(`已安装「${finalTitle}」`, "ok");
    await loadStyles();
    // Auto-select newly installed style
    const sel = document.getElementById("styleSelect");
    if (sel) {
      sel.value = finalId;
      onStyleChange();
    }
    refreshCustomStylesList();
  } catch (e) {
    setStyleManagerStatus(`安装失败：${e.message}`, "error");
  }
}

// ---------------------------------------------------------------------------
// Refresh installed custom styles list
// ---------------------------------------------------------------------------

async function refreshCustomStylesList() {
  const container = document.getElementById("customStylesList");
  if (!container) return;

  try {
    const styles = await fetchJSON("/api/styles");
    const custom  = styles.filter(s => s.builtin === "false");

    if (!custom.length) {
      container.innerHTML = `<div class="custom-styles-empty">尚未安装自定义样式</div>`;
      return;
    }

    container.innerHTML = custom.map(s => `
      <div class="custom-style-item">
        <span class="custom-style-name" title="${escapeHtml(s.id)}">${escapeHtml(s.title)}</span>
        <button class="custom-style-delete" data-id="${escapeHtml(s.id)}" type="button" title="删除此样式">删除</button>
      </div>
    `).join("");

    for (const btn of container.querySelectorAll(".custom-style-delete")) {
      btn.addEventListener("click", async () => {
        const id = btn.dataset.id;
        if (!window.confirm(`确定要删除样式「${id}」吗？`)) return;
        await deleteCustomStyle(id);
      });
    }
  } catch (e) {
    container.innerHTML = `<div class="custom-styles-empty">无法加载样式列表</div>`;
  }
}

// ---------------------------------------------------------------------------
// Delete a custom style via POST /api/styles/delete
// ---------------------------------------------------------------------------

async function deleteCustomStyle(id) {
  setStyleManagerStatus("正在删除…");
  try {
    await fetchJSON("/api/styles/delete", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ id }),
    });
    setStyleManagerStatus("已删除", "ok");
    await loadStyles();
    refreshCustomStylesList();
  } catch (e) {
    setStyleManagerStatus(`删除失败：${e.message}`, "error");
  }
}
