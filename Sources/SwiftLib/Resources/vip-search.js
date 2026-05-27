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

    function toInt(value) {
        return Number.parseInt ? Number.parseInt(value, 10) : Number(value);
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

    function publicationText(root) {
        var authorBlock = root && root.querySelector('.author');
        if (authorBlock) {
            var authorText = clean(authorBlock.innerText || authorBlock.textContent || '');
            if (authorText.indexOf('《') >= 0 && /(?:19|20)\d{2}\s*年/.test(authorText)) {
                return authorText;
            }
        }

        var nodes = Array.prototype.slice.call(root ? root.querySelectorAll('dd') : []);
        for (var i = 0; i < nodes.length; i++) {
            var text = clean(nodes[i].innerText || nodes[i].textContent || '');
            if (text.indexOf('《') >= 0 && /(?:19|20)\d{2}\s*年/.test(text)) return text;
        }
        return '';
    }

    function parsePublicationYear(text) {
        text = clean(text);
        var patterns = [
            /《[^》]+》\s*((?:19|20)\d{2})\s*年第?\s*([0-9A-Za-z增刊特刊-]+)?\s*期?/,
            /(?:出处|来源|期刊|发表时间|出版日期|年份)\s*[:：]?\s*((?:19|20)\d{2})/,
            /(?:^|[^\d])((?:19|20)\d{2})\s*年第?\s*([0-9A-Za-z增刊特刊-]+)?\s*期/
        ];
        for (var i = 0; i < patterns.length; i++) {
            var match = text.match(patterns[i]);
            if (match) {
                return {
                    year: toInt(match[1]),
                    issue: match[2] ? clean(match[2]) : null
                };
            }
        }
        return { year: null, issue: null };
    }

    function extractAbstract(root, text) {
        var abstractBlock = root && root.querySelector('.abstract');
        if (abstractBlock) {
            var candidates = Array.prototype.slice.call(abstractBlock.querySelectorAll('span'))
                .map(function (node) {
                    return clean(node.textContent || '').replace(/\s*展开更多\s*$/, '');
                })
                .filter(function (value) {
                    return value && value !== '展开更多';
                })
                .sort(function (a, b) { return b.length - a.length; });
            if (candidates.length > 0) return candidates[0];
        }

        var abstractMatch = text.match(/共\d+页\s*([\s\S]*?)(?:关键词\s*:|关键词[:：]|关键词\s+|在线阅读|下载PDF|免费下载|$)/);
        if (abstractMatch) return clean(abstractMatch[1]);
        return null;
    }

    function parseArticle(link) {
        var term = link.closest('dt') || link.parentElement;
        var root = term.closest('dl') || term.parentElement || document;
        var text = siblingText(term);
        var title = clean(link.innerText || link.textContent || '');
        if (!title || title.length < 6) return null;

        var authors = Array.prototype.slice.call(root.querySelectorAll('a[href*="key=A"]'))
            .map(function (a) { return clean(a.innerText || a.textContent || ''); })
            .filter(function (name) { return name && name.length <= 20 && name.indexOf('+') !== 0; });

        var journal = null;
        var journalLink = root.querySelector('a[href*="/Qikan/Journal/Summary"]');
        if (journalLink) journal = clean(journalLink.innerText || journalLink.textContent || '').replace(/^《|》$/g, '');
        if (!journal) {
            var journalMatch = text.match(/《([^》]+)》/);
            if (journalMatch) journal = clean(journalMatch[1]);
        }

        var publication = parsePublicationYear(publicationText(root));
        var year = publication.year;
        var issue = publication.issue;

        var pages = null;
        var publicationLine = publicationText(root) || text;
        var pageMatch = publicationLine.match(/第\d+期\s*([0-9]+[-－][0-9]+)/);
        if (!pageMatch) pageMatch = publicationLine.match(/([0-9]+[-－][0-9]+),共\d+页/);
        if (pageMatch) pages = clean(pageMatch[1]).replace('－', '-');

        var abstract = extractAbstract(root, text);

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
