(function() {
  'use strict';

  function meta(names) {
    for (var i = 0; i < names.length; i++) {
      var el = document.querySelector(
        'meta[name="' + names[i] + '"], meta[property="' + names[i] + '"], meta[itemprop="' + names[i] + '"]'
      );
      if (!el) continue;
      var value = (el.getAttribute('content') || '').trim();
      if (value) return value;
    }
    return null;
  }

  function firstText(selectors) {
    for (var i = 0; i < selectors.length; i++) {
      try {
        var el = document.querySelector(selectors[i]);
        if (!el) continue;
        var value = (el.textContent || '').trim();
        if (value) return value;
      } catch (e) {}
    }
    return null;
  }

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

  function extractLabel(labels) {
    var text = pageText();
    if (!text) return null;
    for (var i = 0; i < labels.length; i++) {
      var label = labels[i];
      var regex = new RegExp(label + '\\s*[：:]?\\s*([^\\n]+)');
      var match = text.match(regex);
      if (match && match[1]) return match[1].trim();
    }
    return null;
  }

  function cleanTitle(value) {
    return normalizeText(value)
      .replace(/\s*[-|｜_].*$/, '')
      .replace(/\s*-\s*CNKI.*$/i, '')
      .trim();
  }

  function extractPattern(value, pattern) {
    if (!value) return null;
    var match = value.match(pattern);
    return match ? match[1] || match[0] : null;
  }

  function splitNames(value) {
    if (!value) return [];
    return value
      .split(/[;；/／,，]/)
      .map(function(item) { return normalizeText(item); })
      .filter(Boolean);
  }

  var title =
    meta(['og:title', 'citation_title']) ||
    firstText(['h1', '.title', '.detail-title', '.book-title']) ||
    extractLabel(['书名', '题名', '标题']) ||
    cleanTitle(document.title || '');

  var authorValue = extractLabel(['作者', '著者']);
  var editorValue = extractLabel(['编者', '主编', '编辑']);
  var publisher = extractLabel(['出版社']);
  var isbnValue = extractLabel(['ISBN', '书号']);
  var pagesValue = extractLabel(['总页数', '页数']);
  var abstractValue = extractLabel(['摘要', '内容简介', '内容介绍']);
  var dateValue = extractLabel(['出版时间', '出版年', '出版日期']);

  var authors = splitNames(authorValue || editorValue);
  var result = {
    title: cleanTitle(title),
    authors: authors,
    publisher: normalizeText(publisher),
    isbn: extractPattern(isbnValue, /([0-9Xx-]{10,20})/),
    pages: extractPattern(pagesValue, /(\d{1,6})/),
    abstract: normalizeText(abstractValue),
    date: extractPattern(dateValue, /((?:19|20)\d{2})/),
    url: window.location.href,
    siteName: 'CNKI e-Books',
    itemType: 'book',
    _sources: { siteAdapter: true, adapterId: 'cnki-ebooks' },
  };

  return JSON.stringify(result);
})();
