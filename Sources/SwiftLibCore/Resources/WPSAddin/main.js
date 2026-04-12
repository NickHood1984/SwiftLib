/**
 * SwiftLib WPS Add-in — Entry point (main.js)
 *
 * Loaded by WPS via index.html. Registers ribbon button callbacks,
 * creates the task pane, and hooks document lifecycle events.
 */

const SWIFTLIB_SERVER = "http://127.0.0.1:23858";
// NOTE: GetUrlPath() must be called lazily (inside a function), NOT at module level.
// WPS hasn't finished initialising the add-in environment when main.js is first parsed.

let taskPane = null;
let taskPaneVisible = false;
let ribbonUI = null;

// ── Add-in init (called by ribbon onLoad) ──

function OnAddinLoad(ribbon) {
  ribbonUI = ribbon;
  return true;
}

// ── Ribbon callbacks ──

function OnInsertCitation() {
  ensureTaskPane(true);
  if (taskPane && taskPane.Visible) {
    try {
      taskPane.JSObject && taskPane.JSObject.focusInsertMode && taskPane.JSObject.focusInsertMode();
    } catch (_) { /* cross-frame; ignored — taskpane will handle via message */ }
  }
}

function OnInsertBibliography() {
  try {
    const app = wps.WpsApplication();
    const doc = app.ActiveDocument;
    if (!doc) return;
    const sel = app.ActiveWindow.Selection;
    // Delegate to task pane logic via a server round-trip
    _insertBibliographyAtSelection(doc, sel);
  } catch (e) {
    alert("插入参考文献失败: " + e.message);
  }
}

function OnRefreshAll() {
  ensureTaskPane(true);
  // Post a message to the task pane asking it to trigger a full refresh
  try {
    if (taskPane && taskPane.JSObject && taskPane.JSObject.triggerRefreshAll) {
      taskPane.JSObject.triggerRefreshAll();
    }
  } catch (_) {
    // fallback: the task pane will auto-refresh when opened
  }
}

function OnShowPane() {
  ensureTaskPane(true);
}

// ── Task Pane management ──

function ensureTaskPane(show) {
  // Reuse existing taskpane if still alive (tracked via PluginStorage)
  if (!taskPane) {
    var savedId = wps.PluginStorage.getItem("sl_taskpane_id");
    if (savedId && savedId !== "0") {
      try { taskPane = wps.GetTaskPane(parseInt(savedId)); } catch (_) {}
    }
  }
  if (!taskPane) {
    // WPS on Mac must receive a file:// URL — a bare absolute path gets
    // misinterpreted as a relative HTTP URL and opened in the browser.
    var homePath = wps.Env.GetHomePath();
    var taskpaneURL = "file://" + homePath
      + "/.kingsoft/wps/jsaddons/SwiftLib_1.0/wps-taskpane.html";
    taskPane = wps.CreateTaskPane(taskpaneURL, "");
    if (taskPane) {
      taskPane.Width = 380;
      wps.PluginStorage.setItem("sl_taskpane_id", taskPane.ID);
    }
  }
  if (show && taskPane) {
    taskPane.Visible = true;
    taskPaneVisible = true;
  }
}

// ── Bibliography insert helper (quick path from ribbon) ──

async function _insertBibliographyAtSelection(doc, sel) {
  try {
    // Read metadata first — use known bookmark names from metadata
    // instead of iterating ALL document bookmarks (which freezes WPS).
    let meta = null;
    try {
      const v = doc.Variables.Item("swiftlib_data");
      if (v && v.Value) meta = JSON.parse(v.Value);
    } catch (_) { /* no metadata yet */ }

    if (!meta || !meta.citations || !meta.citations.length) {
      alert("文档中未找到完整的引文元数据，请先使用任务窗格插入引文。");
      return;
    }

    const style = (meta.preferences && meta.preferences.style) || "apa";

    // Build render payload
    const citPayload = meta.citations.map((c, idx) => ({
      key: c.citationId,
      ids: c.refIds || [],
      position: idx,
      citationItems: c.citationItems || null,
    }));

    const resp = await fetch(SWIFTLIB_SERVER + "/api/render-document", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        style: style,
        citations: citPayload,
        items: meta.items || {},
      }),
    });
    const data = await resp.json();
    if (data.error) {
      alert("渲染失败: " + data.error);
      return;
    }

    // Insert bibliography text at selection
    const bibText = data.bibliographyText || "";
    if (!bibText.trim()) {
      alert("参考文献为空。");
      return;
    }

    // Check if bibliography bookmark already exists
    let bibBm = null;
    try {
      bibBm = doc.Bookmarks.Item("sl_bib");
    } catch (_) { /* not found */ }

    if (bibBm) {
      // Update existing bibliography
      bibBm.Range.Text = bibText;
    } else {
      // Insert at cursor
      sel.TypeText(bibText);
      const rng = sel.Range;
      rng.Start = rng.End - bibText.length;
      doc.Bookmarks.Add("sl_bib", rng);
    }
  } catch (e) {
    alert("插入参考文献失败: " + e.message);
  }
}

// ── Document events ──

try {
  wps.ApiEvent.AddApiEventListener("DocumentOpen", function () {
    // Task pane will auto-detect citations on load
  });
} catch (_) {
  // Events may not be available in all WPS versions
}
