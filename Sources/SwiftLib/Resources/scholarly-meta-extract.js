// scholarly-meta-extract.js
// 通用学术网页元数据提取脚本
// 支持：Highwire Press / Google Scholar meta tags, Dublin Core, Open Graph,
//        Schema.org JSON-LD, Bepress
// 注入到 WKWebView，返回 JSON 字符串

(function() {
  'use strict';

  // ── 辅助函数 ──────────────────────────────────────────────────────────────

  function metaContent(names) {
    for (var i = 0; i < names.length; i++) {
      var name = names[i];
      var el = document.querySelector(
        'meta[name="' + name + '"], meta[property="' + name + '"], meta[itemprop="' + name + '"]'
      );
      if (el) {
        var val = (el.getAttribute('content') || '').trim();
        if (val) return val;
      }
    }
    return null;
  }

  function metaContentAll(names) {
    var values = [];
    for (var i = 0; i < names.length; i++) {
      var name = names[i];
      var els = document.querySelectorAll(
        'meta[name="' + name + '"], meta[property="' + name + '"], meta[itemprop="' + name + '"]'
      );
      for (var j = 0; j < els.length; j++) {
        var val = (els[j].getAttribute('content') || '').trim();
        if (val) values.push(val);
      }
    }
    return values;
  }

  function stripHTML(s) {
    if (!s) return null;
    return s.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim() || null;
  }

  // ── 1. Highwire Press / Google Scholar meta tags ──────────────────────────

  function extractHighwire() {
    var result = {};
    result.title = metaContent(['citation_title']);
    result.authors = metaContentAll(['citation_author', 'citation_authors']);
    result.journal = metaContent(['citation_journal_title', 'citation_journal_abbrev']);
    result.doi = metaContent(['citation_doi']);
    result.volume = metaContent(['citation_volume']);
    result.issue = metaContent(['citation_issue']);
    result.firstPage = metaContent(['citation_firstpage']);
    result.lastPage = metaContent(['citation_lastpage']);
    result.date = metaContent(['citation_date', 'citation_publication_date', 'citation_online_date']);
    result.isbn = metaContent(['citation_isbn']);
    result.issn = metaContent(['citation_issn']);
    result.publisher = metaContent(['citation_publisher']);
    result.language = metaContent(['citation_language']);
    result.abstract = metaContent(['citation_abstract']);
    result.pdfURL = metaContent(['citation_pdf_url']);
    result.keywords = metaContentAll(['citation_keywords']);
    result.conference = metaContent(['citation_conference_title', 'citation_conference']);
    result.dissertation = metaContent(['citation_dissertation_institution']);
    result.technical_report_institution = metaContent(['citation_technical_report_institution']);
    return result;
  }

  // ── 2. Bepress meta tags ─────────────────────────────────────────────────

  function extractBepress() {
    var result = {};
    result.title = metaContent(['bepress_citation_title']);
    result.authors = metaContentAll(['bepress_citation_author']);
    result.journal = metaContent(['bepress_citation_journal_title']);
    result.doi = metaContent(['bepress_citation_doi']);
    result.volume = metaContent(['bepress_citation_volume']);
    result.issue = metaContent(['bepress_citation_issue']);
    result.firstPage = metaContent(['bepress_citation_firstpage']);
    result.lastPage = metaContent(['bepress_citation_lastpage']);
    result.date = metaContent(['bepress_citation_date', 'bepress_citation_online_date']);
    return result;
  }

  // ── 3. Dublin Core ───────────────────────────────────────────────────────

  function extractDublinCore() {
    var result = {};
    result.title = metaContent(['DC.title', 'dc.title', 'DC.Title', 'dcterms.title']);
    result.creators = metaContentAll(['DC.creator', 'dc.creator', 'DC.Creator', 'dcterms.creator']);
    result.identifier = metaContent(['DC.identifier', 'dc.identifier', 'DC.Identifier', 'dcterms.identifier']);
    result.description = metaContent(['DC.description', 'dc.description', 'DC.Description', 'dcterms.description']);
    result.date = metaContent(['DC.date', 'dc.date', 'DC.Date', 'dcterms.date', 'dcterms.issued']);
    result.publisher = metaContent(['DC.publisher', 'dc.publisher', 'DC.Publisher', 'dcterms.publisher']);
    result.language = metaContent(['DC.language', 'dc.language', 'DC.Language', 'dcterms.language']);
    result.type = metaContent(['DC.type', 'dc.type', 'DC.Type', 'dcterms.type']);
    result.source = metaContent(['DC.source', 'dc.source', 'DC.Source', 'dcterms.source']);
    result.rights = metaContent(['DC.rights', 'dc.rights', 'DC.Rights', 'dcterms.rights']);
    return result;
  }

  // ── 4. Open Graph ────────────────────────────────────────────────────────

  function extractOpenGraph() {
    var result = {};
    result.title = metaContent(['og:title']);
    result.description = metaContent(['og:description']);
    result.type = metaContent(['og:type']);
    result.url = metaContent(['og:url']);
    result.siteName = metaContent(['og:site_name']);
    return result;
  }

  // ── 5. Schema.org JSON-LD ────────────────────────────────────────────────

  function extractJSONLD() {
    var scripts = document.querySelectorAll('script[type="application/ld+json"]');
    var candidates = [];

    for (var i = 0; i < scripts.length; i++) {
      try {
        var raw = scripts[i].textContent;
        if (!raw) continue;
        var parsed = JSON.parse(raw);
        // Handle @graph arrays
        var items = Array.isArray(parsed) ? parsed : (parsed['@graph'] ? parsed['@graph'] : [parsed]);
        for (var j = 0; j < items.length; j++) {
          var item = items[j];
          var type = item['@type'];
          if (!type) continue;
          // Normalize type to array
          var types = Array.isArray(type) ? type : [type];
          var scholarly = types.some(function(t) {
            return /^(ScholarlyArticle|AcademicArticle|Article|NewsArticle|BlogPosting|Book|Thesis|Report|TechArticle|MedicalScholarlyArticle|CreativeWork)$/i.test(t);
          });
          if (!scholarly) continue;

          var result = {};
          result.type = types[0];
          result.title = item.headline || item.name || null;

          // Authors
          var authorField = item.author || item.creator;
          if (authorField) {
            var authorList = Array.isArray(authorField) ? authorField : [authorField];
            result.authors = authorList.map(function(a) {
              if (typeof a === 'string') return a;
              return a.name || ((a.givenName || '') + ' ' + (a.familyName || '')).trim() || null;
            }).filter(Boolean);
          }

          result.datePublished = item.datePublished || item.dateCreated || null;
          result.description = item.description || item.abstract || null;
          result.doi = null;
          result.issn = null;
          result.isbn = null;
          result.publisher = null;
          result.journal = null;
          result.volume = null;
          result.issue = null;
          result.pageStart = null;
          result.pageEnd = null;
          result.language = item.inLanguage || null;

          // Identifier (DOI, ISSN, ISBN)
          var ids = item.identifier;
          if (ids) {
            var idList = Array.isArray(ids) ? ids : [ids];
            for (var k = 0; k < idList.length; k++) {
              var id = idList[k];
              if (typeof id === 'string') {
                if (/^10\.\d{4,}/.test(id)) result.doi = id;
              } else if (id && id['@type'] === 'PropertyValue') {
                var pn = (id.propertyID || '').toLowerCase();
                var pv = id.value || '';
                if (pn === 'doi') result.doi = pv;
                else if (pn === 'issn') result.issn = pv;
                else if (pn === 'isbn') result.isbn = pv;
              }
            }
          }

          // sameAs / url may contain DOI
          if (!result.doi) {
            var sameAs = item.sameAs || item.url;
            if (typeof sameAs === 'string' && /doi\.org\//.test(sameAs)) {
              var doiMatch = sameAs.match(/doi\.org\/(10\.\d{4,}\/[^\s]+)/);
              if (doiMatch) result.doi = doiMatch[1];
            }
          }

          // Publisher
          if (item.publisher) {
            result.publisher = typeof item.publisher === 'string' ? item.publisher : (item.publisher.name || null);
          }

          // isPartOf → journal
          if (item.isPartOf) {
            var part = item.isPartOf;
            result.journal = typeof part === 'string' ? part : (part.name || null);
            if (part.issn) result.issn = Array.isArray(part.issn) ? part.issn[0] : part.issn;
          }

          // Pagination
          result.pageStart = item.pageStart || null;
          result.pageEnd = item.pageEnd || null;
          if (item.pagination) {
            var pageParts = item.pagination.split('-');
            if (pageParts.length === 2) {
              result.pageStart = result.pageStart || pageParts[0].trim();
              result.pageEnd = result.pageEnd || pageParts[1].trim();
            }
          }

          // Volume / Issue
          result.volume = item.volumeNumber || null;
          result.issue = item.issueNumber || null;

          // ISBN for books
          if (item.isbn) result.isbn = Array.isArray(item.isbn) ? item.isbn[0] : item.isbn;

          candidates.push(result);
        }
      } catch(e) {
        // Ignore malformed JSON-LD
      }
    }

    // Return best candidate (prefer ScholarlyArticle, then Article, then others)
    if (candidates.length === 0) return null;
    if (candidates.length === 1) return candidates[0];

    var typeRank = { ScholarlyArticle: 0, AcademicArticle: 0, MedicalScholarlyArticle: 0, Article: 1, Book: 1, Thesis: 1 };
    candidates.sort(function(a, b) {
      return (typeRank[a.type] || 9) - (typeRank[b.type] || 9);
    });
    return candidates[0];
  }

  // ── 6. Fallback: basic page info ─────────────────────────────────────────

  function extractFallback() {
    return {
      title: document.title || null,
      description: metaContent(['description']),
      author: metaContent(['author'])
    };
  }

  // ── 合并输出 ─────────────────────────────────────────────────────────────

  var highwire = extractHighwire();
  var bepress = extractBepress();
  var dc = extractDublinCore();
  var og = extractOpenGraph();
  var jsonld = extractJSONLD();
  var fallback = extractFallback();

  // 判断是否有学术 meta tag 命中
  var hasHighwire = !!(highwire.title || highwire.doi);
  var hasBepress = !!(bepress.title || bepress.doi);
  var hasDC = !!(dc.title || dc.identifier);
  var hasJSONLD = !!(jsonld && (jsonld.title || jsonld.doi));

  // 合并字段（优先级：Highwire > Bepress > JSON-LD > Dublin Core > Open Graph > fallback）
  function pick() {
    for (var i = 0; i < arguments.length; i++) {
      var v = arguments[i];
      if (v !== null && v !== undefined && v !== '') return v;
    }
    return null;
  }

  function pickArray() {
    for (var i = 0; i < arguments.length; i++) {
      var v = arguments[i];
      if (Array.isArray(v) && v.length > 0) return v;
    }
    return [];
  }

  var merged = {
    title: pick(highwire.title, bepress.title, jsonld && jsonld.title, dc.title, og.title, fallback.title),
    authors: pickArray(
      highwire.authors,
      bepress.authors,
      jsonld && jsonld.authors,
      dc.creators,
      fallback.author ? [fallback.author] : []
    ),
    doi: pick(highwire.doi, bepress.doi, jsonld && jsonld.doi),
    journal: pick(highwire.journal, bepress.journal, jsonld && jsonld.journal, dc.source),
    volume: pick(highwire.volume, bepress.volume, jsonld && jsonld.volume),
    issue: pick(highwire.issue, bepress.issue, jsonld && jsonld.issue),
    pages: null,
    date: pick(highwire.date, bepress.date, jsonld && jsonld.datePublished, dc.date),
    abstract: pick(highwire.abstract, jsonld && jsonld.description, dc.description, og.description, fallback.description),
    isbn: pick(highwire.isbn, jsonld && jsonld.isbn),
    issn: pick(highwire.issn, jsonld && jsonld.issn),
    publisher: pick(highwire.publisher, jsonld && jsonld.publisher, dc.publisher),
    language: pick(highwire.language, jsonld && jsonld.language, dc.language),
    pdfURL: pick(highwire.pdfURL),
    keywords: pickArray(highwire.keywords),
    url: window.location.href,
    siteName: pick(og.siteName),
    conference: pick(highwire.conference),
    dissertation_institution: pick(highwire.dissertation),
    technical_report_institution: pick(highwire.technical_report_institution),

    // Source tracking
    _sources: {
      highwire: hasHighwire,
      bepress: hasBepress,
      dublinCore: hasDC,
      jsonld: hasJSONLD
    }
  };

  // Build pages from firstPage/lastPage
  var fp = pick(highwire.firstPage, bepress.firstPage, jsonld && jsonld.pageStart);
  var lp = pick(highwire.lastPage, bepress.lastPage, jsonld && jsonld.pageEnd);
  if (fp && lp && fp !== lp) {
    merged.pages = fp + '-' + lp;
  } else if (fp) {
    merged.pages = fp;
  }

  // Strip HTML from abstract
  merged.abstract = stripHTML(merged.abstract);

  // Infer item type
  var itemType = 'webpage';
  if (merged.dissertation_institution) {
    itemType = 'thesis';
  } else if (merged.conference) {
    itemType = 'conferencePaper';
  } else if (merged.isbn && !merged.journal) {
    itemType = 'book';
  } else if (merged.technical_report_institution) {
    itemType = 'report';
  } else if (merged.journal || merged.doi || merged.volume || merged.issue) {
    itemType = 'journalArticle';
  } else if (jsonld && /Book/i.test(jsonld.type)) {
    itemType = 'book';
  } else if (jsonld && /Thesis/i.test(jsonld.type)) {
    itemType = 'thesis';
  } else if (jsonld && /Report|TechArticle/i.test(jsonld.type)) {
    itemType = 'report';
  }
  merged.itemType = itemType;

  return JSON.stringify(merged);
})();
