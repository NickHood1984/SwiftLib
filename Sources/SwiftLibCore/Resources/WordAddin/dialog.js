/* global Office */

const DIALOG_SERVER = "";

const dlgState = {
  selectedIds: new Set(),
  selectedRefs: [],
  allResults: [],
  debounceTimer: null,
  /** "insert" | "edit" */
  mode: "insert",
  /** citationId when mode === "edit" */
  editCitationId: null,
};

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

async function fetchJSON(path) {
  const resp = await fetch(DIALOG_SERVER + path);
  if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
  return resp.json();
}

function sendToParent(obj) {
  Office.context.ui.messageParent(JSON.stringify(obj));
}

function toggleSelection(ref) {
  if (dlgState.selectedIds.has(ref.id)) {
    dlgState.selectedIds.delete(ref.id);
    dlgState.selectedRefs = dlgState.selectedRefs.filter((r) => r.id !== ref.id);
  } else {
    dlgState.selectedIds.add(ref.id);
    dlgState.selectedRefs.push(ref);
  }
  renderChips();
  renderResults(dlgState.allResults);
  updateInsertButton();
}

function removeSelection(id) {
  dlgState.selectedIds.delete(id);
  dlgState.selectedRefs = dlgState.selectedRefs.filter((r) => r.id !== id);
  renderChips();
  renderResults(dlgState.allResults);
  updateInsertButton();
}

function renderChips() {
  const el = document.getElementById("selectedChips");
  const optPanel = document.getElementById("citationOptions");
  const optMultiHint = document.getElementById("optMultiHint");
  if (!dlgState.selectedRefs.length) {
    el.innerHTML = "";
    if (optPanel) optPanel.style.display = "none";
    return;
  }
  el.innerHTML = dlgState.selectedRefs
    .map((r) => {
      const label = r.authors
        ? `${escapeHtml(r.authors.split(",")[0])}${r.year ? " (" + r.year + ")" : ""}`
        : `${escapeHtml(r.title)}${r.year ? " (" + r.year + ")" : ""}`;
      return `<div class="chip"><div class="chip-text">${label}</div><button class="chip-remove" type="button" data-id="${r.id}" aria-label="移除">×</button></div>`;
    })
    .join("");
  el.querySelectorAll(".chip-remove").forEach((btn) => {
    btn.addEventListener("click", () => removeSelection(Number(btn.dataset.id)));
  });
  // Show citation options panel when refs are selected
  if (optPanel) optPanel.style.display = "";
  if (optMultiHint) optMultiHint.style.display = dlgState.selectedRefs.length > 1 ? "" : "none";
}

function getCitationItemOptions() {
  const locator = (document.getElementById("optLocator")?.value || "").trim();
  const label = document.getElementById("optLabel")?.value || "page";
  const prefix = (document.getElementById("optPrefix")?.value || "").trim();
  const suffix = (document.getElementById("optSuffix")?.value || "").trim();
  const suppressAuthor = document.getElementById("optSuppressAuthor")?.checked || false;
  return { locator, label, prefix, suffix, suppressAuthor };
}

function updateInsertButton() {
  const btn = document.getElementById("btnInsert");
  const count = dlgState.selectedRefs.length;
  btn.disabled = count === 0;
  if (dlgState.mode === "edit") {
    btn.textContent = count > 1 ? `更新（${count}）` : "更新";
  } else {
    btn.textContent = count > 1 ? `插入（${count}）` : "插入";
  }
}

function renderEmptyState(title, copy, tone) {
  const classes = tone === "danger" ? "empty is-danger" : "empty";
  document.getElementById("results").innerHTML = `
    <div class="${classes}">
      <div class="empty-title">${escapeHtml(title)}</div>
      <div class="empty-copy">${escapeHtml(copy)}</div>
    </div>
  `;
}

function renderResults(refs) {
  const el = document.getElementById("results");
  if (!refs.length) {
    renderEmptyState("未找到匹配的文献", "试试标题、作者姓氏或年份关键词。");
    return;
  }
  el.innerHTML = refs
    .map((r) => {
      const sel = dlgState.selectedIds.has(r.id) ? " sel" : "";
      return `<div class="ref-item${sel}" data-id="${Number(r.id)}"><div class="ref-title">${escapeHtml(r.title)}</div><div class="ref-meta">${escapeHtml(r.authors || "")}${r.year ? " · " + r.year : ""}</div></div>`;
    })
    .join("");
  el.querySelectorAll(".ref-item").forEach((node) => {
    node.addEventListener("click", () => {
      const id = Number(node.getAttribute("data-id"));
      const ref = refs.find((r) => r.id === id);
      if (ref) toggleSelection(ref);
    });
  });
}

async function runSearch(q) {
  const trimmed = (q || "").trim();
  if (!trimmed) {
    dlgState.allResults = [];
    renderEmptyState("开始搜索", "输入标题、作者或年份关键词，快速挑选文献。");
    return;
  }
  try {
    const refs = await fetchJSON(`/api/search?q=${encodeURIComponent(trimmed)}&limit=25`);
    dlgState.allResults = refs;
    renderResults(refs);
  } catch (e) {
    renderEmptyState("搜索失败，请重试", "暂时无法连接 SwiftLib 检索服务。", "danger");
  }
}

Office.onReady(async () => {
  // Parse URL parameters to detect edit mode
  const urlParams = new URLSearchParams(window.location.search);
  const urlMode = urlParams.get("mode");
  const urlCitationId = urlParams.get("citationId");
  const urlRefIds = urlParams.get("refIds");
  const urlStyle = urlParams.get("style");

  if (urlMode === "edit" && urlCitationId) {
    dlgState.mode = "edit";
    dlgState.editCitationId = urlCitationId;
    // Update dialog header for edit mode
    const h1 = document.getElementById("dlgTitle");
    const intro = document.getElementById("dlgIntro");
    const hint = document.getElementById("dlgHint");
    if (h1) h1.textContent = "编辑引文";
    if (intro) intro.textContent = "修改已选文献，然后点击“更新”保存更改。";
    if (hint) hint.textContent = "单击选择 · 再次单击取消 · 点击“更新”保存所有更改";
  }

  try {
    const styles = await fetchJSON("/api/styles");
    const sel = document.getElementById("styleSel");
    sel.innerHTML = styles.map((s) => `<option value="${escapeHtml(s.id)}">${escapeHtml(s.title)}</option>`).join("");
    // Pre-select style from URL parameter
    if (urlStyle) sel.value = urlStyle;
  } catch {
    document.getElementById("styleSel").innerHTML = '<option value="apa">APA</option>';
  }

  // Pre-load existing refs in edit mode
  if (dlgState.mode === "edit" && urlRefIds) {
    const ids = urlRefIds.split(",").map(Number).filter(Boolean);
    if (ids.length) {
      try {
        const refs = await fetchJSON(`/api/references?ids=${ids.join(",")}`);
        for (const ref of refs) {
          dlgState.selectedIds.add(ref.id);
          dlgState.selectedRefs.push(ref);
        }
        renderChips();
        updateInsertButton();
      } catch (e) {
        console.warn("SwiftLib dialog: failed to preload refs for edit mode", e);
      }
    }
  }

  renderEmptyState("开始搜索", "输入标题、作者或年份关键词，快速挑选文献。");

  document.getElementById("search").addEventListener("input", (ev) => {
    clearTimeout(dlgState.debounceTimer);
    dlgState.debounceTimer = setTimeout(() => runSearch(ev.target.value), 150);
  });

  document.getElementById("btnCancel").addEventListener("click", () => {
    sendToParent({ action: "cancel" });
  });

  document.getElementById("btnInsert").addEventListener("click", () => {
    if (!dlgState.selectedRefs.length) return;
    const styleId = document.getElementById("styleSel").value;
    const opts = getCitationItemOptions();
    // Build citationItems array: first item gets the options, rest are bare
    const citationItems = dlgState.selectedRefs.map((r, idx) => {
      const ci = { itemRef: `lib:${r.id}`, refId: r.id };
      if (idx === 0) {
        if (opts.locator) { ci.locator = opts.locator; ci.label = opts.label; }
        if (opts.prefix) ci.prefix = opts.prefix;
        if (opts.suffix) ci.suffix = opts.suffix;
        if (opts.suppressAuthor) ci.suppressAuthor = true;
      }
      return ci;
    });
    if (dlgState.mode === "edit") {
      sendToParent({
        action: "updateCitation",
        citationId: dlgState.editCitationId,
        refIds: dlgState.selectedRefs.map((r) => r.id),
        citationItems,
        styleId,
      });
    } else {
      sendToParent({
        action: "insertCitation",
        refIds: dlgState.selectedRefs.map((r) => r.id),
        citationItems,
        styleId,
      });
    }
  });
});
