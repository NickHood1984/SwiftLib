// baidu-scholar-search.js
// 在百度学术搜索结果页注入，提取文献列表并返回 JSON。
// 支持新旧两种页面结构。
(function () {
    try {
        var results = [];

        // ──────────────────────────────────────────────
        // 定位结果条目（多选择器策略）
        // ──────────────────────────────────────────────
        var itemEls = [];

        // 新版：.sc_con_list 下的 .sc_default_result
        var v1 = document.querySelectorAll('.sc_con_list .sc_default_result');
        // 新版备选：.result_table 下的 .result_table_listitem
        var v2 = document.querySelectorAll('.result_table_listitem');
        // 旧版：每个 h3.t 的父级 div
        var v3 = document.querySelectorAll('.result.sc_default_result');
        var v4 = document.querySelectorAll('h3.t');

        if (v1.length > 0) {
            itemEls = Array.prototype.slice.call(v1);
        } else if (v2.length > 0) {
            itemEls = Array.prototype.slice.call(v2);
        } else if (v3.length > 0) {
            itemEls = Array.prototype.slice.call(v3);
        } else if (v4.length > 0) {
            // h3.t 模式：用父容器
            itemEls = Array.prototype.map.call(v4, function (h3) {
                return h3.closest('.result') || h3.parentElement || h3;
            });
        }

        for (var i = 0; i < Math.min(itemEls.length, 10); i++) {
            var item = itemEls[i];
            var result = {};

            // ── 标题 & URL ──
            var titleEl = item.querySelector('h3.t > a, .sc_res_title a, a[data-click]');
            if (!titleEl) {
                titleEl = item.querySelector('a[href*="xueshu.baidu.com"], a[href*="/paper/"]');
            }
            if (titleEl) {
                result.title = titleEl.textContent.trim().replace(/\s+/g, ' ');
                result.url = titleEl.href;

                // 从 URL 提取 paperid
                var pidMatch = titleEl.href.match(/paperid=([a-f0-9]+)/);
                if (!pidMatch) pidMatch = titleEl.href.match(/\/paper\/show\/([a-f0-9]+)/);
                if (pidMatch) result.paperId = pidMatch[1];
            } else {
                // 尝试 h3 纯文本
                var h3 = item.querySelector('h3');
                if (h3) result.title = h3.textContent.trim().replace(/\s+/g, ' ');
            }

            if (!result.title || result.title.length < 2) continue;

            // ── 作者 / 期刊 / 年份 ──
            var infoEl = item.querySelector('.sc_res_author, .paper-info, .sc_res_pub_info, .author-info');
            if (infoEl) {
                var infoText = infoEl.textContent || '';

                // 年份
                var yearMatch = infoText.match(/(?:19|20)\d{2}/);
                if (yearMatch) result.year = parseInt(yearMatch[0], 10);

                // 作者链接
                var authorLinks = infoEl.querySelectorAll('a[href*="author="], a[href*="wd="]');
                if (authorLinks.length > 0) {
                    result.authors = Array.prototype.map.call(authorLinks, function (a) {
                        return a.textContent.trim();
                    }).filter(function (t) { return t && t.length < 20; });
                }

                // 期刊名 《xxx》
                var journalMatch = infoText.match(/《([^》]+)》/);
                if (journalMatch) result.journal = journalMatch[1];
            }

            // ── 摘要 ──
            var absEl = item.querySelector('.abstract, .sc_res_abstract, p.abstract');
            if (absEl) result.abstract = absEl.textContent.trim();

            // ── DOI / 来源链接 ──
            var doiEl = item.querySelector('a[href*="doi.org"]');
            if (doiEl) {
                var doiMatch = doiEl.href.match(/10\.\d{4,}\/[^\s"']+/);
                if (doiMatch) result.doi = doiMatch[0];
            }

            results.push(result);
        }

        return JSON.stringify({
            status: 'ok',
            results: results,
            itemCount: itemEls.length,
            pageTitle: document.title,
            pageURL: location.href
        });
    } catch (e) {
        return JSON.stringify({
            status: 'error',
            message: e.message,
            results: [],
            pageTitle: document.title,
            pageURL: location.href
        });
    }
})();
