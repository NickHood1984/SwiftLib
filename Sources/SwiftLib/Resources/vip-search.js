// vip-search.js
// Extract visible journal-paper candidates from CQVIP search result pages.
(function () {
    function clean(text) {
        return (text || '').replace(/\s+/g, ' ').trim();
    }

    function absoluteURL(href) {
        if (!href) return '';
        try { return new URL(href, location.href).href; } catch (_) { return href; }
    }

    function isBlocked() {
        var marker = clean([document.title, location.href, document.body && document.body.innerText].join(' ')).toLowerCase();
        return marker.indexOf('412 precondition') >= 0
            || marker.indexOf('安全验证') >= 0
            || marker.indexOf('访问异常') >= 0
            || marker.indexOf('captcha') >= 0;
    }

    function siblingText(term) {
        var parts = [clean(term.innerText || term.textContent || '')];
        var node = term.nextElementSibling;
        var guard = 0;
        while (node && guard < 8) {
            if (node.tagName && node.tagName.toLowerCase() === 'dt') break;
            parts.push(clean(node.innerText || node.textContent || ''));
            node = node.nextElementSibling;
            guard += 1;
        }
        return clean(parts.join(' '));
    }

    function parseArticle(link) {
        var term = link.closest('dt') || link.parentElement;
        var text = siblingText(term);
        var title = clean(link.innerText || link.textContent || '');
        if (!title || title.length < 6) return null;

        var authors = Array.prototype.slice.call((term.parentElement || document).querySelectorAll('a[href*="key=A"]'))
            .map(function (a) { return clean(a.innerText || a.textContent || ''); })
            .filter(function (name) { return name && name.length <= 20 && name.indexOf('+') !== 0; });

        var journal = null;
        var journalLink = (term.parentElement || document).querySelector('a[href*="/Qikan/Journal/Summary"]');
        if (journalLink) journal = clean(journalLink.innerText || journalLink.textContent || '').replace(/^《|》$/g, '');
        if (!journal) {
            var journalMatch = text.match(/《([^》]+)》/);
            if (journalMatch) journal = clean(journalMatch[1]);
        }

        var year = null;
        var yearMatch = text.match(/((?:19|20)\d{2})年第?(\d+)?期?/);
        if (yearMatch) year = parseInt(yearMatch[1], 10);

        var issue = null;
        if (yearMatch && yearMatch[2]) issue = yearMatch[2];

        var pages = null;
        var pageMatch = text.match(/第\d+期\s*([0-9]+[-－][0-9]+)/);
        if (!pageMatch) pageMatch = text.match(/([0-9]+[-－][0-9]+),共\d+页/);
        if (pageMatch) pages = clean(pageMatch[1]).replace('－', '-');

        var abstract = null;
        var abstractMatch = text.match(/共\d+页\s*([\s\S]*?)(?:关键词\s*:|关键词[:：]|在线阅读|下载PDF|$)/);
        if (abstractMatch) abstract = clean(abstractMatch[1]);

        var sourceRecordID = null;
        var idMatch = (link.getAttribute('href') || '').match(/[?&]id=([^&]+)/);
        if (idMatch) sourceRecordID = decodeURIComponent(idMatch[1]);

        return {
            title: title,
            url: absoluteURL(link.getAttribute('href')),
            authors: authors,
            journal: journal,
            year: year,
            issue: issue,
            pages: pages,
            abstract: abstract,
            sourceRecordID: sourceRecordID
        };
    }

    try {
        var links = Array.prototype.slice.call(document.querySelectorAll('a[href*="/Qikan/Article/Detail"]'));
        var seen = {};
        var results = [];
        for (var i = 0; i < links.length && results.length < 10; i++) {
            var parsed = parseArticle(links[i]);
            if (!parsed) continue;
            var key = parsed.sourceRecordID || parsed.url || parsed.title;
            if (seen[key]) continue;
            seen[key] = true;
            results.push(parsed);
        }

        return JSON.stringify({
            status: isBlocked() ? 'blocked' : 'ok',
            results: results,
            itemCount: links.length,
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
