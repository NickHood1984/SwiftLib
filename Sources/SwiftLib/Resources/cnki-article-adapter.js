(function() {
  'use strict';

  function normalizeText(value) {
    return (value || '')
      .replace(/\u00a0/g, ' ')
      .replace(/\r/g, '')
      .replace(/[ \t]+\n/g, '\n')
      .replace(/\n{3,}/g, '\n\n')
      .trim();
  }

  function pageText() {
    return normalizeText(document.body && document.body.innerText);
  }

  function extractAfterLabel(text, labels) {
    if (!text) return null;
    for (var i = 0; i < labels.length; i++) {
      var label = labels[i];
      var regex = new RegExp(label + '\\s*[：:]?\\s*([\\s\\S]*?)(?=\\n(?:关键词|基金资助|专辑|专题|分类号|在线公开|DOI|收稿|\\d+$|$))', 'm');
      var match = text.match(regex);
      if (match && match[1]) return match[1].trim();
    }
    return null;
  }

  function extractAuthors(text) {
    if (!text) return [];
    // Match: "姓名1,2" pattern (name followed by institution numbers)
    // The text format is: "徐子涵1,2沈剑1,2,3封吉猛1,2,3"
    var authorSection = text.match(/([\u4e00-\u9fff\w]+(?:\d(?:,\d)*)?(?:[\u4e00-\u9fff\w]+(?:\d(?:,\d)*)?)*)\s*\n\s*\d+\./);
    if (!authorSection) return [];
    // Split by Chinese characters followed by digits (institution numbers)
    var raw = authorSection[1];
    var authors = [];
    var current = '';
    for (var i = 0; i < raw.length; i++) {
      var ch = raw[i];
      if (/[\u4e00-\u9fff\w]/.test(ch)) {
        current += ch;
      } else if (/[\d,]/.test(ch)) {
        // This is an institution number - save current author if we have one
        if (current.length > 0) {
          authors.push(current);
          current = '';
        }
        // Skip remaining digits and commas
        while (i + 1 < raw.length && /[\d,]/.test(raw[i + 1])) i++;
      }
    }
    if (current.length > 0) authors.push(current);
    return authors.filter(function(s) { return s.length > 1 && s.length < 20; });
  }

  function extractKeywords(text) {
    if (!text) return [];
    var kwSection = text.match(/关键词[：:\s]*([^\n]+)/);
    if (!kwSection) return [];
    return kwSection[1]
      .split(/[;；]/)
      .map(function(s) { return s.trim(); })
      .filter(function(s) { return s.length > 0; });
  }

  function extractYear(text) {
    if (!text) return null;
    // Try network publish date first
    var match = text.match(/(?:网络首发|在线公开|出版)[时间日期]*[：:\s]*(\d{4})/);
    if (match) return match[1];
    // Try general year pattern
    match = text.match(/(\d{4})[-/]\d{1,2}[-/]\d{1,2}/);
    if (match) return match[1];
    return null;
  }

  function extractJournal(text) {
    if (!text) return null;
    // Journal name is typically before the article title
    var match = text.match(/([\u4e00-\u9fff]{2,20})\s*[.．]\s*(?:查看|收录)/);
    if (match) return match[1];
    // Try meta tag
    var metaJournal = document.querySelector('meta[name="citation_journal_title"]');
    if (metaJournal) return metaJournal.getAttribute('content');
    return null;
  }

  var text = pageText();

  var title = normalizeText(
    document.querySelector('.wx-tit h1')?.textContent ||
    document.querySelector('.detail-title')?.textContent ||
    ''
  );
  // Clean title: remove journal prefix, "自动登录", trailing junk
  title = title
    .replace(/^[\u4e00-\u9fff]{2,20}\s*[.．]\s*/, '')
    .replace(/^自动登录/, '')
    .replace(/\s*附视频\s*$/, '')
    .replace(/\s*网络首发\s*$/, '')
    .trim();

  // Fallback: extract title from body text if h1 didn't work
  if (!title || title.length < 4) {
    var titleMatch = text.match(/(?:录用定稿|网络首发)[\s\S]*?\n\s*([\u4e00-\u9fff][\u4e00-\u9fff\w\s（）()]{4,60})\s*\n/);
    if (titleMatch) title = titleMatch[1].trim();
  }

  var authors = extractAuthors(text);
  var abstract = extractAfterLabel(text, ['摘要']);
  var keywords = extractKeywords(text);
  var year = extractYear(text);
  var journal = extractJournal(text);

  // DOI
  var doi = null;
  var doiMatch = text.match(/DOI[：:\s]*(10\.\d{4,9}\/\S+)/i);
  if (doiMatch) doi = doiMatch[1];

  // Fund info
  var fundInfo = null;
  var fundMatch = text.match(/基金资助[：:\s]*([^\n]+)/);
  if (fundMatch) fundInfo = fundMatch[1].trim();

  var result = {
    title: title,
    authors: authors,
    journal: journal,
    year: year,
    doi: doi,
    abstract: abstract,
    keywords: keywords,
    url: window.location.href,
    siteName: 'CNKI',
    itemType: 'journalArticle',
    _sources: { siteAdapter: true, adapterId: 'cnki-articles' },
  };

  if (fundInfo) result.fundingInfo = fundInfo;

  return JSON.stringify(result);
})();
