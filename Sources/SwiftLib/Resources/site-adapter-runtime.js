// site-adapter-runtime.js
// 通用站点适配器运行时引擎
// 接受一个选择器配置对象，执行 DOM 查询 + 变换，返回标准化 JSON
// 由 SiteAdapterService 动态构建注入脚本时嵌入配置

(function(adapterConfig) {
  'use strict';

  var selectors = adapterConfig.selectors || {};
  var transforms = adapterConfig.transforms || {};
  var result = {};

  // ── 基础 DOM 查询 ─────────────────────────────────────────────────────

  /** 按逗号分隔的选择器列表尝试，返回第一个命中元素的文本或 content 属性 */
  function queryFirst(selectorList) {
    if (!selectorList) return null;
    var parts = selectorList.split(/\s*,\s*/);
    for (var i = 0; i < parts.length; i++) {
      var sel = parts[i].trim();
      if (!sel) continue;
      try {
        // meta 标签：读 content 属性
        if (sel.indexOf('meta[') === 0 || sel.indexOf('meta ') === 0) {
          var el = document.querySelector(sel);
          if (el) {
            var val = (el.getAttribute('content') || '').trim();
            if (val) return val;
          }
          continue;
        }
        var el = document.querySelector(sel);
        if (el) {
          var text = (el.textContent || '').trim();
          if (text) return text;
        }
      } catch (e) {
        // 选择器语法错误，跳过
      }
    }
    return null;
  }

  /** 按逗号分隔的选择器列表查询所有命中元素，收集非空文本 */
  function queryAll(selectorList) {
    if (!selectorList) return [];
    var parts = selectorList.split(/\s*,\s*/);
    var values = [];
    var seen = {};
    for (var i = 0; i < parts.length; i++) {
      var sel = parts[i].trim();
      if (!sel) continue;
      try {
        var isMeta = (sel.indexOf('meta[') === 0 || sel.indexOf('meta ') === 0);
        var els = document.querySelectorAll(sel);
        for (var j = 0; j < els.length; j++) {
          var val = isMeta
            ? (els[j].getAttribute('content') || '').trim()
            : (els[j].textContent || '').trim();
          if (val && !seen[val]) {
            seen[val] = true;
            values.push(val);
          }
        }
        if (values.length > 0) break; // 第一组命中的选择器即可
      } catch (e) {}
    }
    return values;
  }

  // ── 变换函数 ──────────────────────────────────────────────────────────

  /** 应用变换规则到一个值（字符串或数组） */
  function applyTransform(value, rule) {
    if (!value || !rule) return value;

    // match:正则 — 从文本中提取第一个匹配
    if (rule.indexOf('match:') === 0) {
      var pattern = rule.substring(6);
      var text = Array.isArray(value) ? value.join(' ') : value;
      try {
        var regex = new RegExp(pattern);
        var m = text.match(regex);
        if (m) return m[1] || m[0]; // 优先返回捕获组
      } catch (e) {}
      return value;
    }

    // matchLabel:标签:(正则) — 在整个 #info 块或文本中找 "标签:值" 格式
    if (rule.indexOf('matchLabel:') === 0) {
      var labelPattern = rule.substring(11);
      var text = Array.isArray(value) ? value.join(' ') : value;
      try {
        var regex = new RegExp(labelPattern);
        var m = text.match(regex);
        if (m) return m[1] || m[0];
      } catch (e) {}
      return value;
    }

    // split:分隔正则 — 将单个文本拆为数组
    if (rule.indexOf('split:') === 0) {
      var sepPattern = rule.substring(6);
      var text = Array.isArray(value) ? value[0] || '' : value;
      if (!text) return [];
      try {
        var regex = new RegExp(sepPattern);
        return text.split(regex).map(function(s) { return s.trim(); }).filter(Boolean);
      } catch (e) {}
      return [text];
    }

    // text — 仅取纯文本（已经是默认行为，此处显式兜底）
    if (rule === 'text') {
      return Array.isArray(value) ? value.join(', ') : value;
    }

    return value;
  }

  // ── 提取逻辑 ──────────────────────────────────────────────────────────

  // 单值字段
  var singleFields = ['title', 'journal', 'year', 'doi', 'abstract', 'volume', 'issue',
                       'pages', 'isbn', 'issn', 'publisher', 'language', 'pdfURL',
                       'url', 'siteName', 'conference',
                       'dissertation_institution', 'technical_report_institution'];

  for (var i = 0; i < singleFields.length; i++) {
    var field = singleFields[i];
    if (selectors[field]) {
      var val = queryFirst(selectors[field]);
      if (val && transforms[field]) {
        val = applyTransform(val, transforms[field]);
      }
      if (val) result[field] = val;
    }
  }

  // 多值字段
  var multiFields = ['authors', 'keywords'];
  for (var i = 0; i < multiFields.length; i++) {
    var field = multiFields[i];
    if (selectors[field]) {
      var vals = queryAll(selectors[field]);
      if (transforms[field]) {
        // split 变换：如果只拿到一个元素但需要拆分
        if (transforms[field].indexOf('split:') === 0 && vals.length === 1) {
          vals = applyTransform(vals[0], transforms[field]);
        }
      }
      if (vals && vals.length > 0) result[field] = vals;
    }
  }

  // 补充 URL
  if (!result.url) {
    result.url = window.location.href;
  }

  // 补充 siteName
  if (!result.siteName) {
    result.siteName = window.location.hostname;
  }

  // 标记来源
  result.itemType = adapterConfig.referenceType || 'webpage';
  result._sources = { siteAdapter: true, adapterId: adapterConfig.id || 'unknown' };

  // 输出
  return JSON.stringify(result);

})(%%ADAPTER_CONFIG%%);
