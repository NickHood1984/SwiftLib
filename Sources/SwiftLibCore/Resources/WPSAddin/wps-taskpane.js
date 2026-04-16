/**
 * SwiftLib WPS Add-in — Task Pane Logic (wps-taskpane.js)
 *
 * Ported from the Office.js taskpane.js. All Word.run() / ContentControl
 * calls have been replaced with WPSDocument (Bookmark-based) equivalents.
 * Server API calls (fetch /api/*) are identical.
 */

/* global WPSDocument */

const SERVER = "http://127.0.0.1:23858";
function _wpsAuthHeaders(extra) {
  const h = Object.assign({}, extra || {});
  if (window.__SWIFTLIB_TOKEN) h["Authorization"] = "Bearer " + window.__SWIFTLIB_TOKEN;
  return h;
}

// ── State ──

const state = {
  selectedIds: new Set(),
  selectedRefs: [],
  allResults: [],
  citedIds: new Set(),
  debounceTimer: null,
  preferredStyle: null,
  styleCitationKind: {},
  hasBibliography: false,
  citedCount: 0,
  activeResultIndex: 0,
  lastQuery: "",
  editingCitationID: null,
  editingBookmarkName: null,
  /** True when edit mode was entered automatically because cursor moved into a citation bookmark. */
  editEnteredBySelection: false,
  /** Map: bookmarkName → { citationId, refIds, style } for quick lookup */
  citationMap: {},
  /** Whether citation bookmark highlights are currently visible */
  citeMarksVisible: false,
};

let upsertBusy = false;
let refreshBusy = false;
let refreshQueued = false;
let _pendingCaretBookmarkName = null;
let _pendingCaretTypingStyle = null;
/** Deferred metadata write: when style changes, we mark the metadata dirty
 *  and write it lazily (on idle) instead of synchronously inside
 *  refreshAllCitations, which blocks the WPS main thread for 10-30 s. */
let _pendingMeta = null;
let _pendingMetaTimer = null;
let _focusBounceInFlight = false;

function flushPendingMetadata() {
  if (_pendingMeta) {
    clearTimeout(_pendingMetaTimer);
    try { WPSDocument.writeMetadata(_pendingMeta); } catch (_) {}
    _pendingMeta = null;
  }
}

// ── Performance Instrumentation ──
// Kept as a no-op shim so existing call sites stay simple without spamming logs.

const _perf = {
  start() {},
  end() { return 0; },
  flush() {},
};

// ── Helpers ──

function debounce(fn, ms) {
  let t = null;
  return (...args) => {
    clearTimeout(t);
    t = setTimeout(() => fn(...args), ms);
  };
}

function escapeHtml(s) {
  const el = document.createElement("span");
  el.textContent = s || "";
  return el.innerHTML;
}

async function fetchJSON(path) {
  // Abort after 8 s so the UI doesn't hang if SwiftLib is not running
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), 8000);
  try {
    const headers = {};
    if (window.__SWIFTLIB_TOKEN) headers["Authorization"] = "Bearer " + window.__SWIFTLIB_TOKEN;
    const res = await fetch(SERVER + path, { signal: ctrl.signal, headers });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    return res.json();
  } finally {
    clearTimeout(timer);
  }
}

function setStatus(msg, isSuccess) {
  const el = document.getElementById("status");
  if (!el) return;
  el.textContent = msg;
  el.classList.toggle("is-success", !!isSuccess);
}

function showLoadingOverlay(text) {
  const overlay = document.getElementById("loadingOverlay");
  const label = document.getElementById("loadingOverlayText");
  if (label && text) label.textContent = text;
  if (overlay) { overlay.classList.add("is-visible"); overlay.setAttribute("aria-busy", "true"); }
}

function hideLoadingOverlay() {
  const overlay = document.getElementById("loadingOverlay");
  if (overlay) { overlay.classList.remove("is-visible"); overlay.setAttribute("aria-busy", "false"); }
}

// Trigger a brief app-switch (SwiftLib → WPS) so WPS re-reads the document
// cursor's character format. Required after citation insert (to clear superscript
// from subsequent typing) and after style refresh (to force WPS repaint).
function triggerFocusBounce() {
  if (_focusBounceInFlight) return;

  _focusBounceInFlight = true;
  fetch(`${SERVER}/api/wps/focus-bounce`, {
    method: "POST",
    headers: _wpsAuthHeaders({ "Content-Type": "application/json" }),
    body: JSON.stringify({ delayMs: 150 }),
  })
    .catch((error) => {
      console.warn("SwiftLib WPS: focus bounce workaround failed:", error);
    })
    .finally(() => {
      _focusBounceInFlight = false;
    });
}

function getStyleSelectElements() {
  return {
    select: document.getElementById("styleSelect"),
    button: document.getElementById("styleSelectButton"),
    buttonLabel: document.getElementById("styleSelectButtonLabel"),
    menu: document.getElementById("styleSelectMenu"),
  };
}

function closeStyleMenu() {
  const { button, menu } = getStyleSelectElements();
  if (menu) menu.classList.remove("is-open");
  if (button) button.setAttribute("aria-expanded", "false");
}

function openStyleMenu() {
  const { button, menu } = getStyleSelectElements();
  if (menu) menu.classList.add("is-open");
  if (button) button.setAttribute("aria-expanded", "true");
}

function toggleStyleMenu() {
  const { menu } = getStyleSelectElements();
  if (!menu) return;
  if (menu.classList.contains("is-open")) closeStyleMenu();
  else openStyleMenu();
}

function syncStyleSelectUI() {
  const { select, buttonLabel, menu } = getStyleSelectElements();
  if (!select || !buttonLabel) return;

  const selectedIndex = select.selectedIndex >= 0 ? select.selectedIndex : 0;
  const selectedOption = select.options[selectedIndex] || null;
  buttonLabel.textContent = selectedOption ? (selectedOption.textContent || selectedOption.value) : "选择样式";

  if (!menu) return;
  Array.from(menu.querySelectorAll(".style-option")).forEach((optionButton) => {
    const isSelected = optionButton.dataset.styleId === select.value;
    optionButton.classList.toggle("is-selected", isSelected);
    optionButton.setAttribute("aria-selected", isSelected ? "true" : "false");
  });
}

function renderStyleSelectMenu() {
  const { select, menu } = getStyleSelectElements();
  if (!select || !menu) return;

  menu.innerHTML = "";
  Array.from(select.options).forEach((opt) => {
    const item = document.createElement("button");
    item.type = "button";
    item.className = "style-option";
    item.dataset.styleId = opt.value;
    item.setAttribute("role", "option");
    item.innerHTML = `<span>${escapeHtml(opt.textContent || opt.value)}</span><span class="style-option-check" aria-hidden="true">✓</span>`;
    item.addEventListener("click", () => {
      const styleSelect = getStyleSelectElements().select;
      if (!styleSelect) return;
      styleSelect.value = opt.value;
      syncStyleSelectUI();
      closeStyleMenu();
      onStyleChange();
    });
    menu.appendChild(item);
  });

  syncStyleSelectUI();
}

// ── Styles ──

async function loadStyles() {
  try {
    const styles = await fetchJSON("/api/styles");
    const sel = document.getElementById("styleSelect");
    sel.innerHTML = "";
    for (const s of styles) {
      const opt = document.createElement("option");
      opt.value = s.id;
      opt.textContent = s.title;
      sel.appendChild(opt);
      state.styleCitationKind[s.id] = s.citationKind;
    }

    // Restore style: localStorage first (most-recently-set by user), then doc metadata
    const lsStyle = (() => { try { return localStorage.getItem("swiftlib_preferred_style"); } catch (_) { return null; } })();
    const meta = WPSDocument.readMetadata();
    if (lsStyle) {
      sel.value = lsStyle;
    } else if (meta && meta.preferences && meta.preferences.style) {
      sel.value = meta.preferences.style;
    }
    state.preferredStyle = sel.value;
    renderStyleSelectMenu();
    // NOTE: The "change" event is wired in init() → onStyleChange() so that
    // style switches trigger a debounced document re-render.
  } catch (e) {
    console.error("SwiftLib WPS: failed to load styles:", e);
  }
}

// ── Search ──

async function search(query) {
  state.lastQuery = query;
  const trimmed = query.trim();
  if (!trimmed) { clearResults(); return; }

  try {
    const startedAt = performance.now();
    const refs = await fetchJSON(`/api/search?q=${encodeURIComponent(trimmed)}&limit=30`);
    state.allResults = refs;
    state.activeResultIndex = refs.length ? 0 : -1;
    renderResults(refs);
    const elapsed = Math.round(performance.now() - startedAt);
    setStatus(`${refs.length} 条结果 "${trimmed}" (${elapsed}ms)`);
  } catch (e) {
    setStatus(`无法连接 SwiftLib: ${e.message}`);
    renderEmpty("无法连接 SwiftLib。");
  }
}

const debouncedSearch = debounce((q) => search(q), 280);

// ── Selection (chip-based multi-select) ──

function addSelection(ref) {
  if (state.selectedIds.has(ref.id)) return;
  state.selectedIds.add(ref.id);
  state.selectedRefs.push(ref);
  renderChips();
  updateButtonState();
  updateCitationOptionsVisibility();
}

function removeSelection(id) {
  state.selectedIds.delete(id);
  state.selectedRefs = state.selectedRefs.filter((r) => r.id !== id);
  renderChips();
  updateButtonState();
  updateCitationOptionsVisibility();
}

function clearSelection() {
  state.selectedIds.clear();
  state.selectedRefs = [];
  state.editingCitationID = null;
  state.editingBookmarkName = null;
  state.editEnteredBySelection = false;
  renderChips();
  updateButtonState();
  updateCitationOptionsVisibility();
  hideEditBanner();
}

function renderChips() {
  const wrap = document.getElementById("selectionTokens");
  if (!wrap) return;
  wrap.innerHTML = state.selectedRefs
    .map((ref, i) => {
      const title = escapeHtml(ref.title || "Untitled");
      return `<span class="chip" data-id="${ref.id}">
        <span class="chip-index">${i + 1}</span>
        <span class="chip-text">${title}</span>
        <button class="chip-remove" data-id="${ref.id}" title="移除">&times;</button>
      </span>`;
    })
    .join("");

  wrap.querySelectorAll(".chip-remove").forEach((btn) => {
    btn.addEventListener("click", (e) => {
      e.stopPropagation();
      removeSelection(Number(btn.dataset.id));
    });
  });
}

function updateButtonState() {
  const btn = document.getElementById("primaryBtn");
  if (!btn) return;
  const hasSelection = state.selectedRefs.length > 0;
  btn.disabled = !hasSelection;
  btn.textContent = state.editingCitationID ? "更新引文" : "插入引文";
}

function updateCitationOptionsVisibility() {
  const panel = document.getElementById("citationOptionsPanel");
  if (!panel) return;
  panel.style.display = state.selectedRefs.length > 0 ? "" : "none";
  const hint = document.getElementById("citOptMultiHint");
  if (hint) hint.classList.toggle("visible", state.selectedRefs.length > 1);
}

// ── Search Results Rendering ──

const REF_TYPE_LABELS = {
  journalArticle: "期刊", book: "书籍", bookSection: "章节",
  conferencePaper: "会议", thesis: "学位论文", webpage: "网页",
  report: "报告", patent: "专利", other: "其他",
};

function renderResults(refs) {
  if (!refs.length) { renderEmpty("未找到文献。"); return; }

  const recentLabel = document.getElementById("recentLabel");
  if (recentLabel && state.lastQuery.trim()) recentLabel.style.display = "none";

  const html = refs
    .map((ref, i) => {
      const selected = state.selectedIds.has(ref.id);
      const active = i === state.activeResultIndex;
      const cited = state.citedIds.has(ref.id);
      const year = ref.year ? ` (${ref.year})` : "";
      const journal = ref.journal ? `<br><em>${escapeHtml(ref.journal)}</em>` : "";
      const citedBadge = cited ? `<span class="cited-badge">已引用</span>` : "";
      const typeBadge = ref.referenceType && REF_TYPE_LABELS[ref.referenceType]
        ? `<span class="ref-type-badge">${REF_TYPE_LABELS[ref.referenceType]}</span>` : "";
      const checkMark = selected ? `<span class="ref-item-check" aria-label="已选中">✓</span>` : "";
      return `<div class="ref-item ${selected ? "selected" : ""} ${active ? "active" : ""} ${cited ? "ref-cited" : ""}" data-id="${ref.id}" style="display:flex;align-items:flex-start;gap:8px;">
        <div style="flex:1;min-width:0;">
          <div class="ref-title">${typeBadge}${escapeHtml(ref.title)}${citedBadge}</div>
          <div class="ref-meta">${escapeHtml(ref.authors)}${year}${journal}</div>
        </div>
        ${checkMark}
      </div>`;
    })
    .join("");

  const results = document.getElementById("results");
  const recentLabelHtml = recentLabel ? recentLabel.outerHTML : "";
  results.innerHTML = recentLabelHtml + html;

  results.querySelectorAll(".ref-item").forEach((el) => {
    el.addEventListener("click", () => {
      const id = Number(el.dataset.id);
      const ref = state.allResults.find((r) => r.id === id);
      if (!ref) return;
      if (state.selectedIds.has(id)) removeSelection(id);
      else addSelection(ref);
      renderResults(state.allResults); // re-render to update selected state
    });

    el.addEventListener("dblclick", () => {
      const id = Number(el.dataset.id);
      const ref = state.allResults.find((r) => r.id === id);
      if (!ref) return;
      if (!state.selectedIds.has(id)) addSelection(ref);
      upsertCitation();
    });
  });
}

function renderEmpty(msg) {
  const results = document.getElementById("results");
  results.innerHTML = `<div class="empty">
    <div class="empty-icon">📚</div>
    <div class="empty-title">${escapeHtml(msg)}</div>
  </div>`;
}

function clearResults() {
  const results = document.getElementById("results");
  results.innerHTML = `<div class="empty">
    <div class="empty-icon">📚</div>
    <div class="empty-title">搜索你的文献库</div>
    <div class="empty-copy">输入标题、作者或年份关键词，快速挑选需要插入的来源。</div>
  </div>`;
}

// ── Citation Options ──

function getCitationOptions() {
  const locator = document.getElementById("citOptLocator")?.value.trim() || "";
  const locatorLabel = document.getElementById("citOptLocatorLabel")?.value || "page";
  const prefix = document.getElementById("citOptPrefix")?.value.trim() || "";
  const suffix = document.getElementById("citOptSuffix")?.value.trim() || "";
  const suppressAuthor = document.getElementById("citOptSuppressAuthor")?.checked || false;

  const opts = {};
  if (locator) { opts.locator = locator; opts.label = locatorLabel; }
  if (prefix) opts.prefix = prefix;
  if (suffix) opts.suffix = suffix;
  if (suppressAuthor) opts["suppress-author"] = true;
  return opts;
}

function clearCitationOptions() {
  const el = (id) => document.getElementById(id);
  if (el("citOptLocator")) el("citOptLocator").value = "";
  if (el("citOptPrefix")) el("citOptPrefix").value = "";
  if (el("citOptSuffix")) el("citOptSuffix").value = "";
  if (el("citOptSuppressAuthor")) el("citOptSuppressAuthor").checked = false;
}

// ── Insert / Update Citation ──

async function upsertCitation() {
  if (upsertBusy) return;

  const styleId = document.getElementById("styleSelect").value;
  const ids = state.selectedRefs.map((r) => r.id);
  if (!ids.length) { setStatus("请至少选择一条文献。"); return; }
  const insertionTypingStyle = WPSDocument.captureSelectionParagraphStyle()
    || WPSDocument.captureSelectionTypingStyle();

  upsertBusy = true;
  const primaryBtn = document.getElementById("primaryBtn");
  if (primaryBtn) primaryBtn.disabled = true;
  showLoadingOverlay("正在插入引文…");

  // Flush any deferred metadata write before reading/writing metadata again
  flushPendingMetadata();

  try {
    // Fetch CSL snapshots
    let cslSnapshots = {};
    try {
      const cslItems = await fetchJSON(`/api/cite-items?ids=${ids.join(",")}`);
      for (const item of cslItems) {
        const key = `lib:${item._swiftlibRefId || item.id}`;
        cslSnapshots[key] = item;
      }
    } catch (e) {
      console.warn("SwiftLib WPS: failed to fetch CSL snapshots:", e);
    }

    // Build citation items array
    const opts = getCitationOptions();
    const citationItems = ids.map((id, i) => {
      const item = { itemRef: "lib:" + id };
      if (i === 0 && Object.keys(opts).length) Object.assign(item, opts);
      return item;
    });

    let citationId;
    let bookmarkName;

    if (state.editingCitationID && state.editingBookmarkName) {
      // Edit existing citation
      citationId = state.editingCitationID;
      bookmarkName = state.editingBookmarkName;
    } else {
      // Insert new citation bookmark
      const result = WPSDocument.insertCitationBookmark("[…]");
      citationId = result.citationId;
      bookmarkName = result.bookmarkName;
    }

    // Store bookmark ID in citation map
    const bmId = bookmarkName.substring(WPSDocument.CITE_BM_PREFIX.length);
    state.citationMap[bookmarkName] = { citationId, refIds: ids, style: styleId };

    // Update metadata
    const meta = WPSDocument.updateMetadataForCitation(
      citationId, ids, styleId, citationItems, cslSnapshots
    );
    // Store bmId for position sync
    const citEntry = meta.citations.find((c) => c.citationId === citationId);
    if (citEntry) citEntry._bmId = bmId;
    WPSDocument.writeMetadata(meta);

    // Render all citations via server
    await refreshAllCitations(styleId, false, bookmarkName, insertionTypingStyle);

    // Update cited IDs
    for (const id of ids) state.citedIds.add(id);

    clearSelection();
    clearCitationOptions();
    hideEditBanner();
    setStatus("✓ 引文已插入", true);
    // Bounce focus through SwiftLib so WPS re-reads the caret's character format.
    // Without this, WPS inherits superscript from the adjacent citation bookmark
    // for any text typed immediately after inserting.
    triggerFocusBounce();

    // Flash success on button
    if (primaryBtn) {
      primaryBtn.classList.add("is-success");
      setTimeout(() => primaryBtn.classList.remove("is-success"), 1400);
    }
  } catch (e) {
    console.error("SwiftLib WPS: upsertCitation error:", e);
    setStatus("插入引文失败: " + e.message);
  } finally {
    upsertBusy = false;
    hideLoadingOverlay();
    updateButtonState();
  }
}

// ── Refresh All Citations ──

async function refreshAllCitations(styleOverride, isStyleSwitch, selectionBookmarkName, selectionTypingStyle) {
  if (selectionBookmarkName) _pendingCaretBookmarkName = selectionBookmarkName;
  if (selectionTypingStyle) _pendingCaretTypingStyle = selectionTypingStyle;
  if (refreshBusy) {
    refreshQueued = true;
    return;
  }
  refreshBusy = true;
  refreshQueued = false;
  const caretBookmarkName = _pendingCaretBookmarkName;
  const caretTypingStyle = _pendingCaretTypingStyle;
  _pendingCaretBookmarkName = null;
  _pendingCaretTypingStyle = null;
  const typingStyleSnapshot = caretTypingStyle || WPSDocument.captureSelectionTypingStyle();

  try {
    _perf.start("total");
    _perf.start("readMetadata");
    const meta = WPSDocument.readMetadata();
    _perf.end("readMetadata");
    if (!meta || !meta.citations || !meta.citations.length) {
      updateDocSummary(0, !!WPSDocument.getBibliographyBookmark());
      return;
    }

    const style = styleOverride || meta.preferences?.style || document.getElementById("styleSelect").value;

    // Skip the expensive getCitationBookmarks() IPC scan here — we only need
    // the count (from metadata) and bookmark names (derivable from _bmId).
    // The actual bookmark lookup happens later in updateAllBookmarkTexts().
    const citationCount = meta.citations.length;

    // Build render payload from metadata
    const citPayload = meta.citations.map((c, idx) => ({
      key: c.citationId,
      ids: c.refIds || [],
      position: idx,
      citationItems: c.citationItems || null,
    }));

    // Yield to allow UI repaint before blocking WPS COM
    await new Promise((r) => setTimeout(r, 0));

    const hasBibliography = !!WPSDocument.getBibliographyBookmark();
    _perf.start("fetch /api/render-document");
    const resp = await fetch(SERVER + "/api/render-document", {
      method: "POST",
      headers: _wpsAuthHeaders({ "Content-Type": "application/json" }),
      body: JSON.stringify({
        style,
        citations: citPayload,
        items: meta.items || {},
        includeBibliography: hasBibliography,
      }),
    });

    const data = await resp.json();
    _perf.end("fetch /api/render-document");
    if (data.error) { setStatus("渲染失败: " + data.error); return; }

    // Determine formatting from response
    const fmt = data.citationFormatting || {};
    const superscriptCitIDs = new Set(data.superscriptCitationIDs || []);

    // Build lookup: citationId → bookmarkName (merge citationMap + metadata _bmId)
    const cidToBm = {};
    for (const [bmName, info] of Object.entries(state.citationMap)) {
      cidToBm[info.citationId] = bmName;
    }
    for (const c of meta.citations) {
      if (c._bmId && !cidToBm[c.citationId]) {
        cidToBm[c.citationId] = WPSDocument.CITE_BM_PREFIX + c._bmId;
      }
    }

    // Collect all updates then write in reverse document order (prevents position-shift bugs)
    const updates = [];
    for (const [citId, renderedText] of Object.entries(data.citationTexts || {})) {
      const bmName = cidToBm[citId];
      if (!bmName) continue;
      const citFmt = { ...fmt };
      if (superscriptCitIDs.has(citId)) citFmt.superscript = true;
      updates.push({ name: bmName, text: renderedText, formatting: citFmt });
    }
    // During style switches, skip the per-bookmark "has text changed?" read
    // (saves 1 IPC per bookmark) since ALL texts are guaranteed to change.
    _perf.start(`updateAllBookmarkTexts (${updates.length} bookmarks)`);
    let lastProgressUpdate = 0;
    await WPSDocument.updateAllBookmarkTexts(updates, (done, total) => {
      const now = Date.now();
      if (done !== total && done % 10 !== 0 && now - lastProgressUpdate < 120) return;
      lastProgressUpdate = now;
      setStatus(`正在更新引文 ${done}/${total}…`);
    }, !!isStyleSwitch);
    _perf.end(`updateAllBookmarkTexts (${updates.length} bookmarks)`);

    // Update bibliography if present
    _perf.start("upsertBibliography");
    if (hasBibliography && data.bibliographyText) {
      WPSDocument.upsertBibliography(data.bibliographyText);
    }
    _perf.end("upsertBibliography");

    // Persist updated style preference — deferred.
    // Writing 100KB+ JSON through synchronous WPS IPC freezes the UI for 10-30 s.
    // Instead, schedule the write for idle time so the user regains control immediately.
    meta.preferences = meta.preferences || {};
    meta.preferences.style = style;
    _pendingMeta = meta;
    clearTimeout(_pendingMetaTimer);
    _pendingMetaTimer = setTimeout(() => {
      if (_pendingMeta) {
        _perf.start("writeMetadata (deferred)");
        try { WPSDocument.writeMetadata(_pendingMeta); } catch (_) {}
        _perf.end("writeMetadata (deferred)");
        _pendingMeta = null;
      }
    }, 2000);

    // Update cited IDs for result list badges
    state.citedIds.clear();
    for (const c of meta.citations) {
      for (const id of (c.refIds || [])) state.citedIds.add(id);
    }
    state.citedCount = citationCount;
    updateDocSummary(citationCount, !!WPSDocument.getBibliographyBookmark());
    if (state.allResults.length) renderResults(state.allResults);

    _perf.end("total");

  } catch (e) {
    console.error("SwiftLib WPS: refreshAllCitations error:", e);
    setStatus("刷新引文失败: " + e.message);
  } finally {
    try {
      if (caretBookmarkName) {
        WPSDocument.ensureTypingGuardAfterBookmark(caretBookmarkName, typingStyleSnapshot);
        WPSDocument.moveSelectionAfterBookmark(caretBookmarkName);
      }
    } catch (_) {}
    try {
      WPSDocument.restoreSelectionTypingStyle(typingStyleSnapshot);
    } catch (_) {}
    try {
      WPSDocument.resetCaretSuperscript();
    } catch (_) {}
    refreshBusy = false;
    // If a refresh was queued while we were busy, run it now
    if (refreshQueued) {
      refreshQueued = false;
      setTimeout(() => refreshAllCitations(), 0);
    }
  }
}

// ── Insert Bibliography ──

async function insertBibliography() {
  showLoadingOverlay("正在插入参考文献…");
  flushPendingMetadata();
  try {
    const meta = WPSDocument.readMetadata();
    if (!meta || !meta.citations || !meta.citations.length) {
      setStatus("文档中未找到引文，无法生成参考文献表。");
      hideLoadingOverlay();
      return;
    }

    const style = meta.preferences?.style || document.getElementById("styleSelect").value;
    const citPayload = meta.citations.map((c, idx) => ({
      key: c.citationId,
      ids: c.refIds || [],
      position: idx,
      citationItems: c.citationItems || null,
    }));

    const resp = await fetch(SERVER + "/api/render-document", {
      method: "POST",
      headers: _wpsAuthHeaders({ "Content-Type": "application/json" }),
      body: JSON.stringify({ style, citations: citPayload, items: meta.items || {} }),
    });
    const data = await resp.json();
    if (data.error) { setStatus("渲染失败: " + data.error); hideLoadingOverlay(); return; }

    const bibText = data.bibliographyText || "";
    if (!bibText.trim()) { setStatus("参考文献为空。"); hideLoadingOverlay(); return; }

    WPSDocument.upsertBibliography(bibText);
    meta.bibliography = true;
    WPSDocument.writeMetadata(meta);

    setStatus("✓ 参考文献已插入", true);
  } catch (e) {
    setStatus("插入参考文献失败: " + e.message);
  } finally {
    hideLoadingOverlay();
  }
}

// ── Finalize (convert to plain text) ──

function finalizeToPlainText() {
  if (!confirm("最终定稿将移除所有 SwiftLib 引文标记，转为纯文字。此操作不可撤销。确定继续？")) return;

  try {
    const doc = WPSDocument.getActiveDoc();
    if (!doc) return;

    // Remove all citation bookmarks (keep text)
    const bmCount = doc.Bookmarks.Count;
    for (let i = bmCount; i >= 1; i--) {
      try {
        const bm = doc.Bookmarks.Item(i);
        const name = bm.Name;
        if (name && (name.indexOf("sl_c_") === 0 || name === "sl_bib" || name === "sl_meta_json")) {
          bm.Delete();
        }
      } catch (_) { /* skip */ }
    }

    // Clear metadata variable
    try {
      doc.Variables.Item("swiftlib_data").Delete();
    } catch (_) { /* may not exist */ }

    setStatus("✓ 已转为纯文字，引文标记已清除。", true);
    updateDocSummary(0, false);
  } catch (e) {
    setStatus("定稿失败: " + e.message);
  }
}

// ── Document Summary ──

function updateDocSummary(citCount, hasBib) {
  const el = document.getElementById("docSummary");
  if (!el) return;
  if (citCount === 0) {
    el.textContent = "无引文";
  } else {
    el.textContent = `${citCount} 条引文${hasBib ? " · 参考文献表" : ""}`;
  }
}

// ── Document Scan (initial load) ──

function scanDocument() {
  try {
    // Read metadata first — if it has known bookmark names we can use the
    // fast path and skip the expensive full-bookmarks scan entirely.
    const meta = WPSDocument.readMetadata();

    // Build known names from metadata so getCitationBookmarks can use the fast path
    const knownBmNames = (meta && meta.citations || [])
      .filter(c => c._bmId)
      .map(c => WPSDocument.CITE_BM_PREFIX + c._bmId);

    const bookmarks = WPSDocument.getCitationBookmarks(knownBmNames.length ? knownBmNames : undefined);
    const hasBib = !!WPSDocument.getBibliographyBookmark();

    // Rebuild citation map
    state.citationMap = {};
    state.citedIds.clear();

    if (meta && meta.citations) {
      for (const c of meta.citations) {
        if (c._bmId) {
          const bmName = WPSDocument.CITE_BM_PREFIX + c._bmId;
          state.citationMap[bmName] = { citationId: c.citationId, refIds: c.refIds || [], style: c.style };
        }
        for (const id of (c.refIds || [])) state.citedIds.add(id);
      }
    }

    state.citedCount = bookmarks.length;
    state.hasBibliography = hasBib;
    updateDocSummary(bookmarks.length, hasBib);

    if (bookmarks.length > 0) {
      setStatus(`已扫描文档: ${bookmarks.length} 条引文`);
    } else {
      setStatus("文档中无 SwiftLib 引文");
    }
  } catch (e) {
    console.error("SwiftLib WPS: scanDocument error:", e);
    setStatus("扫描文档失败");
  }
}
// ── Helper: edit banner ──

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
  updateButtonState();
}

// ── Debounced auto-refresh + style change ──

const debouncedStyleRefresh = debounce(async () => {
  if (refreshBusy) {
    refreshQueued = true;
    return;
  }
  // Pass isStyleSwitch=true so bookmark updates skip the "unchanged" check
  await refreshAllCitations(undefined, true);
  if (refreshQueued) {
    refreshQueued = false;
    await refreshAllCitations(undefined, true);
  }
}, 350);

function onStyleChange() {
  const newStyle = document.getElementById("styleSelect").value;
  if (!newStyle) return;
  if (newStyle === state.preferredStyle) {
    syncStyleSelectUI();
    return;
  }
  state.preferredStyle = newStyle;
  syncStyleSelectUI();
  // Save to localStorage only — DO NOT write document metadata here.
  // Writing the full metadata JSON (which can be 100KB+) through WPS IPC on every
  // style switch causes a 10-30 second freeze because WPS processes the large
  // Variable write synchronously. The preference will be persisted to the document
  // the next time refreshAllCitations() actually renders and calls writeMetadata().
  try { localStorage.setItem("swiftlib_preferred_style", newStyle); } catch (_) {}

  // Fast path: if no citations exist in the document, skip the expensive refresh
  // entirely — there is nothing to re-render.
  if (state.citedCount === 0) {
    setStatus("✓ 样式已切换", true);
    return;
  }

  // Trigger debounced re-render of all citations (with style-switch optimization)
  debouncedStyleRefresh();
}

// ── Repair & Refresh (Word: repairAndRefresh) ──

async function repairAndRefresh() {
  const overflowMenu = document.getElementById("overflowMenu");
  if (overflowMenu) overflowMenu.classList.remove("is-open");
  showLoadingOverlay("正在修复并刷新引文…");
  flushPendingMetadata();
  try {
    const meta = WPSDocument.readMetadata();
    if (meta && meta.citations && meta.citations.length) {
      const bookmarks = WPSDocument.getCitationBookmarks();
      const existingBmNames = new Set(bookmarks.map((b) => b.name));
      const before = meta.citations.length;
      // Remove citations whose bookmark no longer exists
      meta.citations = meta.citations.filter((c) => {
        const bmName = WPSDocument.CITE_BM_PREFIX + (c._bmId || "");
        return existingBmNames.has(bmName);
      });
      // Rebuild positions from document order
      const bmOrder = bookmarks.map((b) => b.name);
      for (const c of meta.citations) {
        const bmName = WPSDocument.CITE_BM_PREFIX + (c._bmId || "");
        const idx = bmOrder.indexOf(bmName);
        if (idx >= 0) c.position = idx;
      }
      meta.citations.sort((a, b) => (a.position || 0) - (b.position || 0));
      WPSDocument.writeMetadata(meta);
      const removed = before - meta.citations.length;
      if (removed > 0) setStatus(`已移除 ${removed} 条孤立引文条目，正在刷新…`);
    }
    await refreshAllCitations();
    setStatus("✓ 修复完成", true);
  } catch (e) {
    setStatus("修复失败: " + e.message);
  } finally {
    hideLoadingOverlay();
  }
}

// ── Restore citation options panel from a citationItems record ──

function restoreCitationItemOptions(item) {
  const el = (id) => document.getElementById(id);
  if (!item) return;
  if (el("citOptLocator"))       el("citOptLocator").value          = item.locator             || "";
  if (el("citOptLocatorLabel"))  el("citOptLocatorLabel").value     = item.label               || "page";
  if (el("citOptPrefix"))        el("citOptPrefix").value           = item.prefix              || "";
  if (el("citOptSuffix"))        el("citOptSuffix").value           = item.suffix              || "";
  if (el("citOptSuppressAuthor")) el("citOptSuppressAuthor").checked = !!item["suppress-author"];
}

// ── Cursor-based edit mode detection (WPS alternative to onSelectionChanged) ──

function checkCursorForEditMode() {
  try {
    // Pass known bookmark names so detectCursorCitation can use the fast path
    // instead of iterating ALL document bookmarks (which freezes WPS).
    const knownNames = Object.keys(state.citationMap);
    const result = WPSDocument.detectCursorCitation(knownNames.length ? knownNames : undefined);
    if (!result) {
      // Cursor left all citations — auto-exit edit mode only if we entered it via detection
      if (state.editEnteredBySelection) {
        state.editEnteredBySelection = false;
        state.editingCitationID = null;
        state.editingBookmarkName = null;
        state.selectedIds.clear();
        state.selectedRefs = [];
        renderChips();
        updateButtonState();
        updateCitationOptionsVisibility();
        hideEditBanner();
      }
      return;
    }

    const { bookmarkName, bmId } = result;
    // Don't re-hydrate if already editing the same citation
    if (state.editingCitationID) {
      const meta = WPSDocument.readMetadata();
      const cur = meta && meta.citations && meta.citations.find((c) => c._bmId === bmId);
      if (cur && cur.citationId === state.editingCitationID) return;
    }

    const meta = WPSDocument.readMetadata();
    if (!meta || !meta.citations) return;
    const citEntry = meta.citations.find((c) => c._bmId === bmId);
    if (!citEntry) return;

    state.editingCitationID = citEntry.citationId;
    state.editingBookmarkName = bookmarkName;
    state.editEnteredBySelection = true;

    // Restore style
    if (citEntry.style) {
      const styleSelect = document.getElementById("styleSelect");
      if (styleSelect) {
        styleSelect.value = citEntry.style;
        state.preferredStyle = citEntry.style;
        syncStyleSelectUI();
      }
    }

    const ids = (citEntry.refIds || []).map(Number).filter(Boolean);
    if (!ids.length) {
      showEditBanner("正在编辑引文");
      return;
    }

    fetchJSON(`/api/references?ids=${ids.join(",")}`)
      .then((refs) => {
        state.selectedIds = new Set(refs.map((r) => r.id));
        state.selectedRefs = refs;
        restoreCitationItemOptions(citEntry.citationItems && citEntry.citationItems[0]);
        renderChips();
        updateButtonState();
        const panel = document.getElementById("citationOptionsPanel");
        if (panel) panel.style.display = refs.length > 0 ? "" : "none";
        const label = refs.length
          ? `正在编辑：${refs.slice(0, 3).map((r) => {
              const name = r.authors ? r.authors.split(",")[0].trim() : r.title;
              return name + (r.year ? ` (${r.year})` : "");
            }).join("；") + (refs.length > 3 ? ` 等${refs.length}条` : "")}`
          : "正在编辑引文";
        showEditBanner(label);
        setStatus("光标在引文中 — 可删除或追加文献，点击「更新引文」。");
      })
      .catch(() => showEditBanner("正在编辑引文"));
  } catch (e) {
    console.warn("SwiftLib WPS: checkCursorForEditMode:", e);
  }
}
// ── Toggle Citation Marks (WPS: highlight bookmark ranges) ──

function toggleCitationMarks() {
  const overflowMenu = document.getElementById("overflowMenu");
  if (overflowMenu) overflowMenu.classList.remove("is-open");

  state.citeMarksVisible = !state.citeMarksVisible;
  const show = state.citeMarksVisible;

  // WPS HighlightColorIndex values (Word-compatible constants)
  const HL_BLUE  = 5;  // wdBlue   — citation
  const HL_GREEN = 4;  // wdTeal   — bibliography
  const HL_NONE  = 0;  // wdNoHighlight

  try {
    const doc = WPSDocument.getActiveDoc();
    if (!doc) { setStatus("没有打开的文档。"); return; }

    const bookmarks = WPSDocument.getCitationBookmarks();
    for (const bm of bookmarks) {
      try {
        const bmObj = doc.Bookmarks.Item(bm.name);
        bmObj.Range.HighlightColorIndex = show ? HL_BLUE : HL_NONE;
      } catch (_) {}
    }

    const bibBm = WPSDocument.getBibliographyBookmark();
    if (bibBm) {
      try {
        const bmObj = doc.Bookmarks.Item(WPSDocument.BIB_BM_NAME);
        bmObj.Range.HighlightColorIndex = show ? HL_GREEN : HL_NONE;
      } catch (_) {}
    }

    const btn = document.getElementById("toggleCiteMarksBtn");
    if (btn) btn.textContent = show ? "✓ 显示引用标记" : "显示引用标记";
    setStatus(show
      ? "引用标记已显示（蓝色=引文，绿色=参考文献表）"
      : "引用标记已隐藏。");
  } catch (e) {
    setStatus("切换失败: " + e.message);
  }
}

// ── Public API (called from main.js via JSObject) ──

function focusInsertMode() {
  const input = document.getElementById("searchInput");
  if (input) input.focus();
}

function triggerRefreshAll() {
  showLoadingOverlay("正在刷新所有引文…");
  refreshAllCitations().then(() => {
    hideLoadingOverlay();
    setStatus("✓ 引文已刷新", true);
  }).catch(() => {
    hideLoadingOverlay();
  });
}

// ── Keyboard Navigation ──

function handleKeydown(e) {
  const results = state.allResults;
  if (!results.length) return;

  if (e.key === "ArrowDown") {
    e.preventDefault();
    state.activeResultIndex = Math.min(state.activeResultIndex + 1, results.length - 1);
    renderResults(results);
  } else if (e.key === "ArrowUp") {
    e.preventDefault();
    state.activeResultIndex = Math.max(state.activeResultIndex - 1, 0);
    renderResults(results);
  } else if (e.key === "Enter") {
    e.preventDefault();
    const ref = results[state.activeResultIndex];
    if (ref) {
      if (state.selectedIds.has(ref.id)) {
        // If already selected and Enter pressed, trigger insert
        upsertCitation();
      } else {
        addSelection(ref);
      }
    }
  } else if (e.key === "Escape") {
    if (state.selectedRefs.length) clearSelection();
  } else if (e.key === "Backspace" && !e.target.value && state.selectedRefs.length) {
    e.preventDefault();
    removeSelection(state.selectedRefs[state.selectedRefs.length - 1].id);
  }
}

// ── Init ──

function init() {
  // Search
  const searchInput = document.getElementById("searchInput");
  searchInput.addEventListener("input", () => debouncedSearch(searchInput.value));
  searchInput.addEventListener("keydown", handleKeydown);

  // Buttons
  document.getElementById("primaryBtn").addEventListener("click", () => upsertCitation());
  document.getElementById("insertBibBtn").addEventListener("click", () => insertBibliography());

  // Edit cancel
  document.getElementById("editCancelBtn")?.addEventListener("click", clearSelection);

  // Style selector → auto refresh (debounced)
  document.getElementById("styleSelect")?.addEventListener("change", onStyleChange);
  document.getElementById("styleSelectButton")?.addEventListener("click", (e) => {
    e.stopPropagation();
    toggleStyleMenu();
  });
  document.getElementById("styleSelectMenu")?.addEventListener("click", (e) => e.stopPropagation());

  // Overflow menu
  const overflowBtn = document.getElementById("overflowBtn");
  const overflowMenu = document.getElementById("overflowMenu");
  overflowBtn?.addEventListener("click", (e) => {
    e.stopPropagation();
    overflowMenu.classList.toggle("is-open");
  });
  document.addEventListener("click", () => {
    overflowMenu?.classList.remove("is-open");
    closeStyleMenu();
  });
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape") closeStyleMenu();
  });

  // Refresh button → repair + refresh (removes ghost bookmarks, then re-renders)
  document.getElementById("refreshBtn")?.addEventListener("click", () => repairAndRefresh());

  document.getElementById("toggleCiteMarksBtn")?.addEventListener("click", () => toggleCitationMarks());

  document.getElementById("finalizeBtn")?.addEventListener("click", () => {
    overflowMenu?.classList.remove("is-open");
    finalizeToPlainText();
  });

  // Load styles, then scan document.
  // If SwiftLib server is not running, loadStyles() will throw — catch it gracefully
  // so the panel still renders and shows a helpful message.
  loadStyles()
    .then(() => {
      // Defer document scan to the next event loop tick so the taskpane UI
      // finishes its initial render first and WPS can process pending repaints.
      // Without this, the synchronous IPC calls in scanDocument() block both
      // the taskpane and the WPS document window during init.
      setTimeout(() => {
        try {
          scanDocument();
          // Check if cursor is already inside a citation (e.g. panel opened while editing)
          checkCursorForEditMode();
        } catch (e) {
          console.warn("SwiftLib WPS: initial scan failed:", e);
          setStatus("等待在 WPS 中打开文档…");
        }
      }, 0);
    })
    .catch((e) => {
      console.warn("SwiftLib WPS: loadStyles failed:", e);
      setStatus("请先启动 SwiftLib 应用，再使用面板。");
    });

  updateButtonState();
}

// Start when DOM is ready
if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", init);
} else {
  init();
}
