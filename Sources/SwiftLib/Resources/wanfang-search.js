// wanfang-search.js
// Extract visible journal-paper candidates from Wanfang search result pages.
(function () {
    function clean(text) {
        return (text || '').replace(/\s+/g, ' ').trim();
    }

    function absoluteURL(href) {
        if (!href) return '';
        try { return new URL(href, location.href).href; } catch (_) { return href; }
    }

    function splitChineseAuthorRun(name) {
        name = clean(name);
        if (!/^[\u4e00-\u9fff]{4,}$/.test(name)) return [name];
        var chars = Array.from(name);
        if (chars.length % 3 === 0) {
            var groups3 = [];
            for (var i = 0; i < chars.length; i += 3) groups3.push(chars.slice(i, i + 3).join(''));
            return groups3;
        }
        if (chars.length % 2 === 0) {
            var groups2 = [];
            for (var j = 0; j < chars.length; j += 2) groups2.push(chars.slice(j, j + 2).join(''));
            return groups2;
        }
        return [name];
    }

    function isBlocked() {
        var marker = clean([document.title, location.href, document.body && document.body.innerText].join(' ')).toLowerCase();
        return marker.indexOf('fault filter abort') >= 0
            || marker.indexOf('安全验证') >= 0
            || marker.indexOf('访问异常') >= 0
            || marker.indexOf('captcha') >= 0;
    }

    function parseCandidate(container) {
        var text = clean(container.innerText || container.textContent || '');
        if (!text || text.indexOf('[期刊论文]') < 0) return null;

        var title = '';
        var titleMatch = text.match(/(?:^|\s)(?:\d+\.)\s*(.*?)\s*\[期刊论文\]/);
        if (titleMatch) {
            title = clean(titleMatch[1]);
        }
        if (!title) {
            var beforeType = text.split('[期刊论文]')[0];
            title = clean(beforeType.replace(/^\d+\.\s*/, ''));
        }
        if (!title || title.length < 6) return null;

        var journal = null;
        var journalMatch = text.match(/《([^》]+)》/);
        if (journalMatch) journal = clean(journalMatch[1]);

        var year = null;
        var yearMatch = text.match(/((?:19|20)\d{2})年/);
        if (yearMatch) year = parseInt(yearMatch[1], 10);

        var authors = [];
        var authorsMatch = text.match(/\[期刊论文\]\s*([\s\S]{0,120}?)(?:[-－]\s*)?《/);
        if (authorsMatch) {
            authors = clean(authorsMatch[1])
                .replace(/等$/, '')
                .split(/[,\s，、;；]+/)
                .map(clean)
                .filter(function (name) { return name && name.length <= 20 && name !== '-'; })
                .reduce(function (items, name) {
                    return items.concat(splitChineseAuthorRun(name));
                }, []);
        }

        var abstract = null;
        var abstractMatch = text.match(/摘要[:：]\s*([\s\S]*?)(?:关键词|在线阅读|下载|引用|收藏|被引[:：]|$)/);
        if (abstractMatch) abstract = clean(abstractMatch[1]);

        var detailURL = '';
        var anchors = Array.prototype.slice.call(container.querySelectorAll('a[href]'));
        var detailAnchor = anchors.find(function (a) {
            var href = a.getAttribute('href') || '';
            var label = clean(a.innerText || a.textContent || '');
            return href.indexOf('wanfangdata.com.cn') >= 0
                && href.indexOf('/wf/detail') >= 0
                && label.indexOf('客服') < 0;
        });
        if (detailAnchor) detailURL = absoluteURL(detailAnchor.getAttribute('href'));
        if (!detailURL) detailURL = location.href;

        return {
            title: title,
            url: detailURL,
            authors: authors,
            journal: journal,
            year: year,
            abstract: abstract
        };
    }

    try {
        var results = [];
        var candidates = Array.prototype.slice.call(document.querySelectorAll('div, li, section, article'))
            .filter(function (el) {
                var text = clean(el.innerText || el.textContent || '');
                return text.indexOf('[期刊论文]') >= 0
                    && text.indexOf('摘要') >= 0
                    && text.length >= 80
                    && text.length <= 3000;
            })
            .sort(function (a, b) {
                return clean(a.innerText || a.textContent || '').length
                    - clean(b.innerText || b.textContent || '').length;
            });

        var seen = {};
        for (var i = 0; i < candidates.length && results.length < 10; i++) {
            var parsed = parseCandidate(candidates[i]);
            if (!parsed) continue;
            var key = parsed.title + '|' + (parsed.journal || '') + '|' + (parsed.year || '');
            if (seen[key]) continue;
            seen[key] = true;
            results.push(parsed);
        }

        return JSON.stringify({
            status: isBlocked() ? 'blocked' : 'ok',
            results: results,
            itemCount: candidates.length,
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
