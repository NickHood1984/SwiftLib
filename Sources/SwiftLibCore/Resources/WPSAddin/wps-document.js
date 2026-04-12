/**
 * SwiftLib WPS Add-in — Document Abstraction Layer (wps-document.js)
 *
 * Wraps all WPS JSAPI calls for citation bookmark management,
 * metadata persistence, and text formatting. This is the WPS equivalent
 * of the Office.js Word.run / ContentControl layer.
 *
 * Key differences from Office.js:
 *   - ContentControl → Bookmark (name prefix: sl_c_ for citations, sl_bib for bibliography)
 *   - CustomXmlParts → Document.Variables (or hidden bookmark fallback)
 *   - Synchronous COM-style API (no async ctx.sync() needed)
 *   - Range.Font for formatting (no insertHtml)
 */

const WPSDocument = (function () {
  "use strict";

  const CITE_BM_PREFIX = "sl_c_";
  const CITE_GUARD_BM_PREFIX = "sl_g_";
  const BIB_BM_NAME = "sl_bib";
  const META_VAR_NAME = "swiftlib_data";
  const META_BM_FALLBACK = "sl_meta_json";
  const TYPING_GUARD_CHAR = "\u200C";

  // ── Unique ID generation ──

  function shortId() {
    // 8-char hex ID for bookmark names (sl_c_xxxxxxxx)
    const arr = new Uint8Array(4);
    if (typeof crypto !== "undefined" && crypto.getRandomValues) {
      crypto.getRandomValues(arr);
    } else {
      for (let i = 0; i < 4; i++) arr[i] = Math.floor(Math.random() * 256);
    }
    return Array.from(arr, (b) => b.toString(16).padStart(2, "0")).join("");
  }

  function uuidV4() {
    // Full UUID for citation IDs in metadata
    return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function (c) {
      const r = (Math.random() * 16) | 0;
      const v = c === "x" ? r : (r & 0x3) | 0x8;
      return v.toString(16);
    });
  }

  // ── WPS Application helpers ──

  function getApp() {
    return wps.WpsApplication();
  }

  function getActiveDoc() {
    const app = getApp();
    return app.ActiveDocument || null;
  }

  function getSelection() {
    const app = getApp();
    return app.ActiveWindow ? app.ActiveWindow.Selection : null;
  }

  function hasCollapsedSelectionAt(position) {
    const sel = getSelection();
    if (!sel || typeof position !== "number") return false;

    try {
      return sel.Range && sel.Range.Start === position && sel.Range.End === position;
    } catch (_) {
      return false;
    }
  }

  function setCollapsedSelection(position) {
    if (typeof position !== "number") return false;

    const sel = getSelection();
    if (!sel) return false;

    try {
      if (typeof sel.SetRange === "function") {
        sel.SetRange(position, position);
        if (hasCollapsedSelectionAt(position)) return true;
      }
    } catch (_) {}

    try {
      sel.Start = position;
      sel.End = position;
      if (hasCollapsedSelectionAt(position)) return true;
    } catch (_) {}

    try {
      const rng = sel.Range;
      if (!rng) return false;
      rng.Start = position;
      rng.End = position;
      if (typeof rng.Select === "function") rng.Select();
      if (hasCollapsedSelectionAt(position)) return true;
    } catch (_) {}

    return false;
  }

  function getTypingGuardBookmarkName(bookmarkName) {
    if (!bookmarkName) return null;
    if (bookmarkName.indexOf(CITE_BM_PREFIX) === 0) {
      return CITE_GUARD_BM_PREFIX + bookmarkName.substring(CITE_BM_PREFIX.length);
    }
    return bookmarkName + "_guard";
  }

  function getBookmarkOrNull(bookmarkName) {
    const doc = getActiveDoc();
    if (!doc || !bookmarkName) return null;
    try {
      return doc.Bookmarks.Item(bookmarkName);
    } catch (_) {
      return null;
    }
  }

  // ── Bookmark-based Citation Markers ──

  /**
   * Insert a citation bookmark at the current selection.
   * @param {string} placeholderText - Temporary text (e.g. "[1]") before rendering
   * @returns {{ bookmarkName: string, citationId: string }} identifiers
   */
  function insertCitationBookmark(placeholderText) {
    const doc = getActiveDoc();
    const sel = getSelection();
    if (!doc || !sel) throw new Error("No active document or selection");

    const citationId = uuidV4();
    const bmId = shortId();
    const bookmarkName = CITE_BM_PREFIX + bmId;

    // Insert placeholder text at cursor
    sel.TypeText(placeholderText || "[…]");

    // Select the just-inserted text to create a range for the bookmark
    const rng = sel.Range;
    const textLen = (placeholderText || "[…]").length;
    rng.Start = rng.End - textLen;

    // Create bookmark around the placeholder text
    doc.Bookmarks.Add(bookmarkName, rng);

    // Move cursor past the bookmark
    moveSelectionAfterBookmark(bookmarkName);

    return { bookmarkName, citationId };
  }

  function moveSelectionAfterBookmark(bookmarkName) {
    if (!bookmarkName) return false;

    const guardBookmarkName = getTypingGuardBookmarkName(bookmarkName);
    const bm = getBookmarkOrNull(guardBookmarkName) || getBookmarkOrNull(bookmarkName);
    if (!bm) return false;

    let endPos;
    try {
      endPos = bm.Range.End;
    } catch (_) {
      return false;
    }

    if (setCollapsedSelection(endPos)) return true;

    try {
      const afterRange = bm.Range;
      afterRange.Start = endPos;
      afterRange.End = endPos;
      if (typeof afterRange.Select === "function") afterRange.Select();
      if (hasCollapsedSelectionAt(endPos)) return true;
    } catch (_) {}

    try {
      const afterRange = bm.Range;
      afterRange.Collapse(0); // wdCollapseEnd
      if (typeof afterRange.Select === "function") afterRange.Select();
      if (hasCollapsedSelectionAt(endPos)) return true;
    } catch (_) {}

    try {
      const sel = getSelection();
      if (!sel || typeof sel.Collapse !== "function") return false;
      sel.Collapse(0); // wdCollapseEnd
      return hasCollapsedSelectionAt(endPos);
    } catch (_) {
      return false;
    }
  }

  /**
   * Get all citation bookmarks in the document.
   *
   * @param {string[]} [knownNames] — if provided, look up bookmarks by name (fast path).
   *   This avoids iterating ALL document bookmarks by index, which is very slow on
   *   macOS WPS because it incurs an IPC call for every bookmark including system/hidden
   *   bookmarks. Pass the expected bookmark names from metadata to use this fast path.
   *   Bookmarks that no longer exist (deleted with text) are silently skipped.
   * @returns {Array<{ name: string, text: string, start: number }>}
   */
  function getCitationBookmarks(knownNames) {
    const doc = getActiveDoc();
    if (!doc) return [];

    const result = [];

    if (knownNames && knownNames.length) {
      // Fast path: look up by name — avoids O(N_all_bookmarks) IPC scan
      for (const name of knownNames) {
        try {
          const bm  = doc.Bookmarks.Item(name);
          const rng = bm.Range;
          result.push({ name, text: rng.Text || "", start: rng.Start });
        } catch (_) {
          // Bookmark not found (was deleted along with its text) — skip
        }
      }
      result.sort((a, b) => a.start - b.start);
      return result;
    }

    // Slow fallback: iterate ALL document bookmarks (used on initial scan
    // when we don't yet have metadata to derive known names from).
    const bmCount = doc.Bookmarks.Count;
    for (let i = 1; i <= bmCount; i++) {
      try {
        const bm = doc.Bookmarks.Item(i);
        const name = bm.Name;
        if (name && name.indexOf(CITE_BM_PREFIX) === 0) {
          result.push({
            name: name,
            text: bm.Range.Text || "",
            start: bm.Range.Start,
          });
        }
      } catch (_) {
        // Bookmark may have been deleted during iteration
      }
    }

    // Sort by document position
    result.sort((a, b) => a.start - b.start);
    return result;
  }

  /**
   * Update the text content and formatting of a citation bookmark.
   * @param {string} bookmarkName
   * @param {string} text - New rendered text
   * @param {object} [formatting] - { superscript, bold, italic, underline, smallCaps }
   */
  function updateBookmarkText(bookmarkName, text, formatting) {
    const doc = getActiveDoc();
    if (!doc) return;

    let bm;
    try {
      bm = doc.Bookmarks.Item(bookmarkName);
    } catch (_) {
      console.warn("SwiftLib WPS: bookmark not found:", bookmarkName);
      return;
    }

    const rng = bm.Range;
    const startPos = rng.Start;

    // Replace text (this deletes the bookmark)
    rng.Text = text;

    // Re-select the range and re-create the bookmark
    rng.Start = startPos;
    rng.End = startPos + text.length;

    // Apply formatting if specified
    if (formatting) {
      applyFormatting(rng, formatting);
    }

    // Re-add the bookmark (replacing text removes it)
    doc.Bookmarks.Add(bookmarkName, rng);
  }

  /**
   * Delete a citation bookmark and optionally its text content.
   * @param {string} bookmarkName
   * @param {boolean} [deleteText=false]
   */
  function deleteCitationBookmark(bookmarkName, deleteText) {
    const doc = getActiveDoc();
    if (!doc) return;

    try {
      const bm = doc.Bookmarks.Item(bookmarkName);
      if (deleteText) {
        bm.Range.Text = "";
      }
      bm.Delete();
    } catch (_) {
      // Already gone
    }
  }

  // ── Bibliography Bookmark ──

  function getBibliographyBookmark() {
    const doc = getActiveDoc();
    if (!doc) return null;
    try {
      const bm = doc.Bookmarks.Item(BIB_BM_NAME);
      return { name: BIB_BM_NAME, text: bm.Range.Text || "", range: bm.Range };
    } catch (_) {
      return null;
    }
  }

  function upsertBibliography(text) {
    const doc = getActiveDoc();
    const sel = getSelection();
    if (!doc || !sel) return;

    let bibBm = null;
    try {
      bibBm = doc.Bookmarks.Item(BIB_BM_NAME);
    } catch (_) { /* not found */ }

    if (bibBm) {
      const rng = bibBm.Range;
      const currentText = rng.Text || "";
      if (currentText === text) return;
      const startPos = rng.Start;
      rng.Text = text;
      rng.Start = startPos;
      rng.End = startPos + text.length;
      doc.Bookmarks.Add(BIB_BM_NAME, rng);
    } else {
      sel.TypeText(text);
      const rng = sel.Range;
      rng.Start = rng.End - text.length;
      doc.Bookmarks.Add(BIB_BM_NAME, rng);
    }
  }

  // ── Text Formatting ──

  function hasMeaningfulFormatting(fmt) {
    if (!fmt) return false;
    return fmt.superscript !== undefined
      || fmt.bold !== undefined
      || fmt.italic !== undefined
      || fmt.underline !== undefined
      || fmt.smallCaps !== undefined;
  }

  function applyFormatting(range, fmt) {
    if (!range || !hasMeaningfulFormatting(fmt)) return;
    const font = range.Font;
    if (fmt.superscript === true) font.Superscript = true;
    else if (fmt.superscript === false) font.Superscript = false;

    if (fmt.bold === true) font.Bold = true;
    else if (fmt.bold === false) font.Bold = false;

    if (fmt.italic === true) font.Italic = true;
    else if (fmt.italic === false) font.Italic = false;

    if (fmt.underline === true) font.Underline = 1; // wdUnderlineSingle
    else if (fmt.underline === false) font.Underline = 0; // wdUnderlineNone

    if (fmt.smallCaps === true) font.SmallCaps = true;
    else if (fmt.smallCaps === false) font.SmallCaps = false;
  }

  const TYPING_STYLE_FONT_KEYS = [
    "Name",
    "NameAscii",
    "NameFarEast",
    "NameOther",
    "Size",
    "Color",
    "Bold",
    "Italic",
    "Underline",
    "UnderlineColor",
    "SmallCaps",
    "AllCaps",
    "StrikeThrough",
    "DoubleStrikeThrough",
    "Subscript",
    "Superscript",
    "Spacing",
    "Position",
    "Scaling",
  ];

  function snapshotFont(font) {
    if (!font) return null;

    const snapshot = {};
    for (const key of TYPING_STYLE_FONT_KEYS) {
      try {
        const value = font[key];
        if (value !== undefined && value !== null && typeof value !== "object") {
          snapshot[key] = value;
        }
      } catch (_) {}
    }

    return Object.keys(snapshot).length ? snapshot : null;
  }

  function applyFontSnapshot(font, snapshot) {
    if (!font || !snapshot) return;

    for (const [key, value] of Object.entries(snapshot)) {
      try {
        font[key] = value;
      } catch (_) {}
    }

    if (!Object.prototype.hasOwnProperty.call(snapshot, "Subscript")) {
      try { font.Subscript = false; } catch (_) {}
    }
    if (!Object.prototype.hasOwnProperty.call(snapshot, "Superscript")) {
      try { font.Superscript = false; } catch (_) {}
    }
    try { font.Hidden = false; } catch (_) {}
  }

  function captureRangeParagraphStyle(range) {
    if (!range) return null;

    try {
      const paragraphs = range.Paragraphs;
      if (!paragraphs || typeof paragraphs.Item !== "function") return null;
      const paragraph = paragraphs.Item(1);
      if (!paragraph || !paragraph.Range || !paragraph.Range.Font) return null;
      return snapshotFont(paragraph.Range.Font);
    } catch (_) {
      return null;
    }
  }

  function getSelectionFontTarget() {
    const sel = getSelection();
    if (!sel) return null;

    try {
      if (sel.Range && sel.Range.Font) return sel.Range.Font;
    } catch (_) {}

    try {
      if (sel.Font) return sel.Font;
    } catch (_) {}

    return null;
  }

  function isSelectionCollapsed() {
    const sel = getSelection();
    if (!sel) return false;

    try {
      return sel.Range && sel.Range.Start === sel.Range.End;
    } catch (_) {
      return false;
    }
  }

  function captureSelectionTypingStyle() {
    if (!isSelectionCollapsed()) return null;

    const font = getSelectionFontTarget();
    return snapshotFont(font);
  }

  function captureSelectionParagraphStyle() {
    const sel = getSelection();
    if (!sel) return null;

    try {
      return captureRangeParagraphStyle(sel.Range);
    } catch (_) {
      return null;
    }
  }

  function restoreSelectionTypingStyle(snapshot) {
    if (!snapshot || !isSelectionCollapsed()) return;

    const font = getSelectionFontTarget();
    applyFontSnapshot(font, snapshot);
  }

  // After writing citation bookmarks, explicitly clear superscript on the caret
  // so WPS macOS does not inherit the citation's superscript format for subsequent typing.
  function resetCaretSuperscript() {
    try {
      if (!isSelectionCollapsed()) return;
      const font = getSelectionFontTarget();
      if (!font) return;
      font.Superscript = false;
      font.Subscript = false;
    } catch (_) {}
  }

  function ensureTypingGuardAfterBookmark(bookmarkName, snapshot) {
    const doc = getActiveDoc();
    const sel = getSelection();
    const guardBookmarkName = getTypingGuardBookmarkName(bookmarkName);
    const citationBookmark = getBookmarkOrNull(bookmarkName);
    if (!doc || !sel || !guardBookmarkName || !citationBookmark) return false;

    const guardStyle = snapshot
      || captureRangeParagraphStyle(citationBookmark.Range)
      || captureSelectionParagraphStyle()
      || captureSelectionTypingStyle();

    let guardBookmark = getBookmarkOrNull(guardBookmarkName);
    if (!guardBookmark) {
      let insertPos;
      try {
        insertPos = citationBookmark.Range.End;
      } catch (_) {
        return false;
      }

      if (!setCollapsedSelection(insertPos)) return false;

      try {
        sel.TypeText(TYPING_GUARD_CHAR);
      } catch (_) {
        return false;
      }

      const guardRange = sel.Range;
      guardRange.Start = guardRange.End - TYPING_GUARD_CHAR.length;
      if (guardStyle && guardRange.Font) applyFontSnapshot(guardRange.Font, guardStyle);
      try {
        doc.Bookmarks.Add(guardBookmarkName, guardRange);
      } catch (_) {
        return false;
      }
      guardBookmark = getBookmarkOrNull(guardBookmarkName);
    }

    if (!guardBookmark) return false;

    try {
      const guardRange = guardBookmark.Range;
      const startPos = guardRange.Start;
      if ((guardRange.Text || "") !== TYPING_GUARD_CHAR) {
        guardRange.Text = TYPING_GUARD_CHAR;
        guardRange.Start = startPos;
        guardRange.End = startPos + TYPING_GUARD_CHAR.length;
        doc.Bookmarks.Add(guardBookmarkName, guardRange);
      }
      if (guardStyle && guardRange.Font) applyFontSnapshot(guardRange.Font, guardStyle);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Metadata Persistence (Document Variables / Hidden Bookmark fallback) ──

  let _useVariablesFallback = null; // null = unknown, true = use bookmark fallback

  function _checkVariablesSupport(doc) {
    if (_useVariablesFallback !== null) return;
    try {
      // Attempt to use Document.Variables — may fail on some WPS versions
      doc.Variables.Add("__swiftlib_test", "1");
      doc.Variables.Item("__swiftlib_test").Delete();
      _useVariablesFallback = false;
    } catch (_) {
      _useVariablesFallback = true;
      console.warn("SwiftLib WPS: Document.Variables not supported, using hidden bookmark fallback");
    }
  }

  /**
   * Read the persisted citation metadata from the document.
   * @returns {object|null} Parsed JSON payload or null
   */
  function readMetadata() {
    const doc = getActiveDoc();
    if (!doc) return null;

    _checkVariablesSupport(doc);

    if (!_useVariablesFallback) {
      try {
        const v = doc.Variables.Item(META_VAR_NAME);
        if (v && v.Value) return JSON.parse(v.Value);
      } catch (_) { /* not set yet */ }
      return null;
    }

    // Fallback: hidden bookmark
    try {
      const bm = doc.Bookmarks.Item(META_BM_FALLBACK);
      const text = bm.Range.Text;
      if (text) return JSON.parse(text);
    } catch (_) { /* not found */ }
    return null;
  }

  /** Cache the last written JSON to skip no-op writes (avoids expensive IPC). */
  let _lastWrittenMetaJSON = null;

  /**
   * Write citation metadata to the document.
   * Skips the write if the serialized JSON is identical to the last write.
   * @param {object} payload - JSON-serializable metadata
   */
  function writeMetadata(payload) {
    const doc = getActiveDoc();
    if (!doc) return;

    _checkVariablesSupport(doc);
    const json = JSON.stringify(payload);

    // Skip write when nothing changed — the synchronous IPC for large
    // payloads (100KB+) is the single biggest source of UI freezes.
    if (json === _lastWrittenMetaJSON) return;

    if (!_useVariablesFallback) {
      try {
        const existing = doc.Variables.Item(META_VAR_NAME);
        existing.Value = json;
      } catch (_) {
        // Variable doesn't exist yet — create
        doc.Variables.Add(META_VAR_NAME, json);
      }
      _lastWrittenMetaJSON = json;
      return;
    }

    // Fallback: hidden bookmark at end of document
    try {
      const bm = doc.Bookmarks.Item(META_BM_FALLBACK);
      const rng = bm.Range;
      rng.Text = json;
      rng.Start = rng.End - json.length;
      doc.Bookmarks.Add(META_BM_FALLBACK, rng);
    } catch (_) {
      // Create new hidden bookmark at end of document
      const rng = doc.Content;
      rng.Collapse(0); // wdCollapseEnd
      rng.Text = json;
      rng.Start = rng.End - json.length;
      rng.Font.Size = 1;
      rng.Font.Color = 16777215; // white — effectively hidden
      doc.Bookmarks.Add(META_BM_FALLBACK, rng);
    }
    _lastWrittenMetaJSON = json;
  }

  /**
   * Build or update the full metadata payload.
   * Merges citation data with existing stored metadata.
   */
  function updateMetadataForCitation(citationId, refIds, styleId, citationItems, cslSnapshots) {
    let meta = readMetadata() || { v: 4, preferences: {}, items: {}, citations: [], bibliography: false };

    meta.preferences = meta.preferences || {};
    meta.preferences.style = styleId;

    // Update CSL snapshots
    if (cslSnapshots) {
      meta.items = meta.items || {};
      for (const [key, val] of Object.entries(cslSnapshots)) {
        meta.items[key] = val;
      }
    }

    // Update or add citation entry
    const existing = meta.citations.findIndex((c) => c.citationId === citationId);
    const entry = {
      citationId: citationId,
      refIds: refIds,
      citationItems: citationItems || refIds.map((id) => ({ itemRef: "lib:" + id })),
      style: styleId,
      position: existing >= 0 ? meta.citations[existing].position : meta.citations.length,
    };

    if (existing >= 0) {
      meta.citations[existing] = entry;
    } else {
      meta.citations.push(entry);
    }

    writeMetadata(meta);
    return meta;
  }

  /**
   * Rebuild citation positions from bookmark document order.
   */
  function syncCitationPositions() {
    const bookmarks = getCitationBookmarks();
    const meta = readMetadata();
    if (!meta || !meta.citations) return;

    const bmNameSet = new Set(bookmarks.map((b) => b.name));

    // Remove citations whose bookmarks no longer exist
    meta.citations = meta.citations.filter((c) => {
      // Find bookmark by matching the short ID suffix
      return bookmarks.some((bm) => bm.name === CITE_BM_PREFIX + (c._bmId || ""));
    });

    // Update positions based on document order
    const bmOrder = bookmarks.map((b) => b.name);
    for (const c of meta.citations) {
      const bmName = CITE_BM_PREFIX + (c._bmId || "");
      const idx = bmOrder.indexOf(bmName);
      if (idx >= 0) c.position = idx;
    }

    writeMetadata(meta);
  }

  /**
   * Batch-update multiple citation bookmarks.
   *
   * Performance strategy:
   *  1. Phase 1 (read-only): collect changed bookmarks + cache startPos to skip re-read.
   *  2. Phase 1 caches the Range proxy object itself — Phase 2 reuses it instead of
   *     calling Bookmarks.Item() + bm.Range() again (saves 2 IPC round-trips per bookmark).
   *  3. Tries Application.ScreenUpdating = false (helps on Windows WPS; may be ignored
   *     on macOS WPS, which is fine — the bulk write still completes correctly).
   *  4. Yields ONCE before writing (so the taskpane can render the loading message)
   *     and ONCE after (so WPS can repaint). Do NOT yield per-item — on macOS WKWebView
   *     each setTimeout(0) is throttled to ~100-300ms, so N yields = N×300ms = many
   *     seconds for a modest citation count.
   *  5. Calls the optional onProgress(done, total) callback after each write.
   *  6. Always restores ScreenUpdating in finally.
   *
   * @param {Array<{ name: string, text: string, formatting?: object }>} updates
   * @param {((done: number, total: number) => void) | null} [onProgress]
   * @param {boolean} [skipUnchangedCheck=false] — pass true during style switches
   *   when ALL citation texts are guaranteed to change, skipping the expensive
   *   Phase 1 read (saves 4 IPC calls per bookmark).
   * @returns {Promise<void>}
   */
  async function updateAllBookmarkTexts(updates, onProgress, skipUnchangedCheck) {
    if (!updates || !updates.length) return;
    const doc = getActiveDoc();
    const app = getApp();
    if (!doc) return;

    const bmData = [];

    if (skipUnchangedCheck) {
      // Fast mode: skip reading current text — assume all bookmarks need updating.
      // Only need 2 IPC per bookmark (Item + Range.Start) instead of 4.
      for (const u of updates) {
        try {
          const bm  = doc.Bookmarks.Item(u.name);   // IPC 1
          const rng = bm.Range;                      // IPC 2
          const startPos = rng.Start;                // IPC 3
          bmData.push({ name: u.name, text: u.text, formatting: u.formatting, startPos, rng });
        } catch (_) {}
      }
    } else {
      // Normal mode: skip unchanged bookmarks + cache Range objects.
      for (const u of updates) {
        try {
          const bm  = doc.Bookmarks.Item(u.name);   // IPC 1
          const rng = bm.Range;                      // IPC 2
          const current = rng.Text || "";            // IPC 3
          if (current === u.text) continue;
          const startPos = rng.Start;                // IPC 4
          bmData.push({ name: u.name, text: u.text, formatting: u.formatting, startPos, rng });
        } catch (_) {}
      }
    }
    if (!bmData.length) return;

    // Reverse-order: write end-of-doc first so position values for earlier
    // bookmarks remain valid when we reach them.
    bmData.sort((a, b) => b.startPos - a.startPos);

    // Yield once before writing so the taskpane UI can show the loading indicator.
    await new Promise((r) => setTimeout(r, 0));

    // Best-effort: disable screen redraw while writing.
    // On macOS WPS this property may be silently ignored, but on desktop
    // Windows WPS it provides a measurable speedup.
    let screenWasUpdating = true;
    try {
      screenWasUpdating = app.ScreenUpdating;
      app.ScreenUpdating = false;
    } catch (_) {}

    const total = bmData.length;
    // NOTE: Do NOT yield (setTimeout) between individual bookmark writes.
    // On macOS WKWebView, each setTimeout(0) is throttled to ~100-300ms,
    // so N yields = N×300ms of pure delay.  It is faster to batch all
    // writes together and let WPS process them without interruption.
    try {
      for (let i = 0; i < total; i++) {
        const d = bmData[i];
        try {
          // Reuse cached Range — avoids Bookmarks.Item + bm.Range IPC each iteration
          const rng = d.rng;
          rng.Text  = d.text;                      // IPC 1 (write, destroys bookmark)
          rng.Start = d.startPos;                  // IPC 2 (re-anchor after text change)
          rng.End   = d.startPos + d.text.length;  // IPC 3
          if (d.formatting) applyFormatting(rng, d.formatting); // IPC 4-6
          doc.Bookmarks.Add(d.name, rng);          // IPC 5-7 (recreate bookmark)
        } catch (_) {
          // Cached rng may have been invalidated — fall back to a fresh lookup
          try {
            const bm2  = doc.Bookmarks.Item(d.name);
            const rng2 = bm2.Range;
            rng2.Text  = d.text;
            rng2.Start = d.startPos;
            rng2.End   = d.startPos + d.text.length;
            if (d.formatting) applyFormatting(rng2, d.formatting);
            doc.Bookmarks.Add(d.name, rng2);
          } catch (_2) {}
        }

        if (onProgress && ((i + 1) === total || ((i + 1) % 10) === 0)) onProgress(i + 1, total);
      }
    } finally {
      try { app.ScreenUpdating = screenWasUpdating; } catch (_) {}
    }
    // Yield once after all writes so WPS can repaint the document.
    await new Promise((r) => setTimeout(r, 0));
  }

  // ── Cursor Detection ──

  /**
   * Detect if the cursor is inside a citation bookmark.
   * @param {string[]} [knownNames] — if provided, only check these bookmark names
   *   (fast path). Falls back to iterating ALL bookmarks if not provided.
   * @returns {{ bookmarkName: string, bmId: string }|null}
   */
  function detectCursorCitation(knownNames) {
    const doc = getActiveDoc();
    const sel = getSelection();
    if (!doc || !sel) return null;

    const cursorStart = sel.Range.Start;
    const cursorEnd = sel.Range.End;

    if (knownNames && knownNames.length) {
      // Fast path: only check known citation bookmarks by name — avoids
      // iterating ALL document bookmarks (system/hidden) which is very slow.
      for (const name of knownNames) {
        try {
          const bm = doc.Bookmarks.Item(name);
          const bmStart = bm.Range.Start;
          const bmEnd = bm.Range.End;
          if (cursorStart >= bmStart && cursorEnd <= bmEnd) {
            const bmId = name.substring(CITE_BM_PREFIX.length);
            return { bookmarkName: name, bmId: bmId };
          }
        } catch (_) {
          continue;
        }
      }
      return null;
    }

    // Slow fallback: iterate ALL document bookmarks
    const bmCount = doc.Bookmarks.Count;
    for (let i = 1; i <= bmCount; i++) {
      try {
        const bm = doc.Bookmarks.Item(i);
        const name = bm.Name;
        if (!name || name.indexOf(CITE_BM_PREFIX) !== 0) continue;

        const bmStart = bm.Range.Start;
        const bmEnd = bm.Range.End;

        if (cursorStart >= bmStart && cursorEnd <= bmEnd) {
          // Cursor is inside this citation bookmark
          const bmId = name.substring(CITE_BM_PREFIX.length);
          return { bookmarkName: name, bmId: bmId };
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  // ── Public API ──

  return {
    CITE_BM_PREFIX,
    BIB_BM_NAME,

    // ID generation
    shortId,
    uuidV4,

    // WPS accessors
    getApp,
    getActiveDoc,
    getSelection,

    // Citation bookmarks
    insertCitationBookmark,
    getCitationBookmarks,
    moveSelectionAfterBookmark,
    updateBookmarkText,
    deleteCitationBookmark,

    // Bibliography
    getBibliographyBookmark,
    upsertBibliography,

    // Formatting
    applyFormatting,
    captureSelectionTypingStyle,
    captureSelectionParagraphStyle,
    restoreSelectionTypingStyle,
    resetCaretSuperscript,
    ensureTypingGuardAfterBookmark,

    // Batch bookmark update (performance)
    updateAllBookmarkTexts,

    // Metadata
    readMetadata,
    writeMetadata,
    updateMetadataForCitation,
    syncCitationPositions,

    // Cursor detection
    detectCursorCitation,
  };
})();
