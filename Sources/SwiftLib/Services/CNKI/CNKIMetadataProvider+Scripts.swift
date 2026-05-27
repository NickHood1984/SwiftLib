import Foundation

extension CNKIMetadataProvider {
    static var pageAssessmentScript: String {
        scriptWithSelectorConfig(pageAssessmentScriptTemplate)
    }

    static var searchExtractionScript: String {
        scriptWithSelectorConfig(searchExtractionScriptTemplate)
    }

    static var detailExtractionScript: String {
        scriptWithSelectorConfig(detailExtractionScriptTemplate)
    }

    private static func scriptWithSelectorConfig(_ template: String) -> String {
        let groups = CNKISelectorService.shared.config.groups
        let data = (try? JSONEncoder().encode(groups)) ?? Data("{}".utf8)
        let json = String(data: data, encoding: .utf8) ?? "{}"
        return template.replacingOccurrences(of: "%%CNKI_SELECTORS%%", with: json)
    }

    private static let pageAssessmentScriptTemplate = #"""
    (() => {
      const configuredSelectors = %%CNKI_SELECTORS%%;
      const selectorGroup = (name, fallback) => {
        const value = configuredSelectors?.[name];
        return Array.isArray(value) && value.length > 0 ? value : fallback;
      };
      const normalize = (value) => String(value || "").replace(/\s+/g, " ").trim();
      const isVisible = (el) => {
        if (!el) return false;
        const style = window.getComputedStyle(el);
        if (style.display === 'none' || style.visibility === 'hidden') return false;
        const rect = el.getBoundingClientRect();
        return rect.width > 0 && rect.height > 0;
      };
      const cleanAuthor = (value) => normalize(value)
        .replace(/[\d０-９¹²³⁴⁵⁶⁷⁸⁹]+$/g, '')
        .replace(/[\*†‡#]+$/g, '')
        .trim();
      const isLikelyAuthorToken = (value) => {
        const cleaned = cleanAuthor(value);
        if (!cleaned) return false;
        return /^[\u3400-\u9FFF]{2,4}(?:·[\u3400-\u9FFF]{1,6})?$/.test(cleaned)
          || /^[A-Za-z][A-Za-z .'-]{1,60}$/.test(cleaned);
      };
      const isLikelyAuthorLine = (line) => {
        const normalized = normalize(line);
        if (!normalized) return false;
        const numberedMatches = Array.from(
          normalized.matchAll(/([\u3400-\u9FFF]{2,4}(?:·[\u3400-\u9FFF]{1,6})?)(?=\s*[0-9０-９¹²³⁴⁵⁶⁷⁸⁹])/g)
        )
          .map((match) => cleanAuthor(match[1]))
          .filter(isLikelyAuthorToken);
        if (numberedMatches.length >= 2) return true;
        const segments = normalized
          .split(/[，,；;、|\s]+/)
          .map(cleanAuthor)
          .filter(Boolean);
        return segments.length >= 2 && segments.every(isLikelyAuthorToken);
      };
      const isSuspiciousTitle = (value) => {
        const normalized = normalize(value);
        if (!normalized || normalized.length > 160) return true;
        const lowered = normalized.toLowerCase();
        const badTokens = ['cnki', '中国知网', 'network first', 'doi', 'journal', 'issn', 'online first'];
        const exactBadTitles = ['自动登录', '用户登录', '机构用户登录', '安全验证', '访问异常', '异常访问', '验证码'];
        if (badTokens.some((token) => lowered.includes(token))) return true;
        if (exactBadTitles.includes(normalized)) return true;
        if (normalized.length <= 12 && (normalized.includes('登录') || normalized.includes('验证'))) return true;
        if (lowered.startsWith('author') || lowered.startsWith('title')) return true;
        if (/^\d+$/.test(normalized)) return true;
        return false;
      };
      const rawPageText = String(document.body?.innerText || "");
      const marker = normalize((document.title || "") + " " + rawPageText.slice(0, 1800));
      const searchRowCount = document.querySelectorAll(selectorGroup('searchRows', [
        'table.result-table-list > tbody > tr',
        '.result-table-list tbody tr',
        '.result-table tbody tr',
        'tr[data-dbcode]'
      ]).join(',')).length;
      const hasVisibleVerificationUI = Array.from(document.querySelectorAll('input, iframe, img, div, span, p, a, button'))
        .filter(isVisible)
        .some((el) => {
          const text = normalize(el.innerText || el.textContent || "");
          const hint = normalize(`${el.className || ''} ${el.id || ''} ${el.getAttribute?.('placeholder') || ''} ${el.getAttribute?.('aria-label') || ''}`).toLowerCase();
          return (!!text && text.length <= 120 && /安全验证|请完成验证|验证码|访问异常|异常访问|验证后继续访问/.test(text))
            || /(captcha|validate)/.test(hint);
        });
      const hasSearchEmptyState = searchRowCount === 0 && (
        /抱歉，暂无数据|暂无数据|未找到相关文献|未检索到相关文献|没有找到相关结果|请稍后重试/.test(rawPageText.slice(0, 4000))
        || !!document.querySelector('.nodata, .no-data, .result-none, [class*="nodata"], [class*="no-data"], [class*="noresult"], [class*="no-result"], [class*="empty-data"]')
      );
      const blockedSignals = /安全验证|请完成验证|验证码|访问异常|异常访问|验证后继续访问/.test(marker) || hasVisibleVerificationUI;
      const lines = rawPageText
        .replace(/\r/g, '')
        .split(/\n+/)
        .map(normalize)
        .filter(Boolean)
        .slice(0, 40);
      const contextualTitle = lines.find((line) =>
        line.length >= 6
        && line.length <= 80
        && /[\u3400-\u9FFF]/.test(line)
        && !isLikelyAuthorLine(line)
        && !/^(文献知网节|摘要|关键词|基金资助|专辑|专题|分类号|DOI|doi)/.test(line)
        && !/[0-9]{4}.*\([0-9]{2}\)|查看该刊数据库收录/.test(line)
        && !/[:：]/.test(line)
      ) || "";
      const headingTitles = Array.from(document.querySelectorAll(selectorGroup('detailTitle', [
        '.wx-tit > h1',
        '.xx_title > h1',
        '.title > h1',
        '.brief h1',
        'h1'
      ]).join(',')))
        .filter(isVisible)
        .map((el) => normalize(el.innerText || el.textContent || ""))
        .filter(Boolean);
      const titleCandidates = [
        document.querySelector('meta[name="citation_title"]')?.getAttribute('content'),
        ...headingTitles,
        contextualTitle,
      ]
        .map(normalize)
        .filter((value) => !!value && !isLikelyAuthorLine(value));
      const visibleTitle = titleCandidates.find((value) => !isSuspiciousTitle(value)) || titleCandidates[0] || "";
      const hasDetailTitle = !!visibleTitle && !isSuspiciousTitle(visibleTitle);
      const hasDetailAuthors = document.querySelectorAll([
        ...selectorGroup('detailAuthors', [
          '.author a',
          '.authors a',
          '.wx-tit .author a',
          '.author-list a',
          '#authorpart a',
          '.brief .author a',
          '.xx_title .author a'
        ]),
        'meta[name="citation_author"]'
      ].join(',')).length > 0 || /[\u3400-\u9FFF]{2,4}(?:·[\u3400-\u9FFF]{1,6})?\s*[0-9０-９¹²³⁴⁵⁶⁷⁸⁹]/.test(rawPageText.slice(0, 1600));
      const hasDetailSummary = !!document.querySelector(selectorGroup('detailAbstract', [
        '#ChDivSummary',
        '.summary',
        '.abstract',
        '.abstract-text'
      ]).join(','))
        || /(?:摘要|abstract)\s*[:：]/i.test(rawPageText.slice(0, 4000));
      const hasVisibleDetailScaffold = hasDetailTitle && (hasDetailAuthors || hasDetailSummary);
      const markerBlocked = blockedSignals && !hasVisibleDetailScaffold && !hasSearchEmptyState;
      return JSON.stringify({
        markerBlocked,
        searchRowCount,
        hasSearchEmptyState,
        hasDetailTitle,
        hasDetailAuthors,
        hasDetailSummary,
        hasVisibleDetailScaffold,
        blockedReason: markerBlocked ? (hasVisibleVerificationUI ? 'verification-ui' : 'verification-marker') : null
      });
    })();
    """#

    private static let searchExtractionScriptTemplate = #"""
    (() => {
      const configuredSelectors = %%CNKI_SELECTORS%%;
      const selectorGroup = (name, fallback) => {
        const value = configuredSelectors?.[name];
        return Array.isArray(value) && value.length > 0 ? value : fallback;
      };
      const normalize = (value) => String(value || "").replace(/\s+/g, " ").trim();
      const pageText = normalize(document.body?.innerText || "");
      const marker = normalize((document.title || "") + " " + pageText.slice(0, 4000));
      const blocked = /安全验证|请完成验证|验证码|访问异常|异常访问|验证后继续访问/.test(marker);
      const seen = new Set();
      const candidates = [];

      const firstText = (container, selectors) => {
        for (const selector of selectors) {
          const el = container?.querySelector?.(selector);
          const value = normalize(el?.textContent || el?.innerText || "");
          if (value) return value;
        }
        return "";
      };

      for (const anchor of Array.from(document.querySelectorAll(selectorGroup('searchCandidateAnchors', [
        'a[href]',
        'a[data-href]'
      ]).join(',')))) {
        const rawHref = anchor.getAttribute('href') || anchor.getAttribute('data-href') || '';
        if (!rawHref || rawHref.startsWith('javascript:')) continue;

        let href = '';
        try {
          href = new URL(rawHref, location.href).href;
        } catch {
          continue;
        }

        if (!/(detail|KCMS|kcms2\/article\/abstract|detail\.aspx|kns\/detail)/i.test(href)) continue;

        const title = normalize(anchor.textContent || anchor.getAttribute('title') || "");
        if (!title || title.length < 4) continue;

        const container = anchor.closest('tr, li, article, .result-table-list, .result-table, .list-item, .record-item, .item, .brief, .result-item') || anchor.parentElement || document.body;
        const authorText = firstText(container, selectorGroup('searchAuthor', ['td.author', '.author', '.authors', '[class*="author"]']));
        const sourceText = firstText(container, selectorGroup('searchSource', ['td.source', '.source', '.journal', '[class*="source"]']));
        const dateText = firstText(container, selectorGroup('searchDate', ['td.date', '.date', '.year', '[class*="date"]']));
        const citationText = firstText(container, selectorGroup('searchCitation', ['td.quote', '.quote', '.citation', '[class*="quote"]']));
        const metaText = [authorText, sourceText, dateText, citationText]
          .filter(Boolean)
          .join(' | ');
        const snippetEl = container?.querySelector?.(selectorGroup('searchSnippet', [
          '.abstract',
          '.summary',
          '.brief',
          '.item-summary',
          '.item-abstract',
          'p'
        ]).join(','));
        const snippet = normalize(snippetEl?.textContent || "");
        const exportNode = container?.querySelector?.('[data-dbname][data-filename]');
        const exportIDNode = container?.querySelector?.('td.seq input, .seq input, input[value]');
        const exportID = normalize(exportIDNode?.value || exportIDNode?.getAttribute?.('value') || "");
        const dbname = normalize(exportNode?.getAttribute?.('data-dbname') || "");
        const filename = normalize(exportNode?.getAttribute?.('data-filename') || "");
        const key = href + '|' + title;
        if (seen.has(key)) continue;
        seen.add(key);
        candidates.push({
          title,
          detailURL: href,
          metaText,
          snippet: snippet || null,
          exportID: exportID || null,
          dbname: dbname || null,
          filename: filename || null
        });
      }

      const emptyState = candidates.length === 0 && (
        /抱歉，暂无数据|暂无数据|未找到相关文献|未检索到相关文献|没有找到相关结果|请稍后重试/.test(pageText)
        || !!document.querySelector('.nodata, .no-data, .result-none, [class*="nodata"], [class*="no-data"], [class*="noresult"], [class*="no-result"], [class*="empty-data"]')
      );

      return JSON.stringify({
        blocked,
        emptyState,
        candidates: candidates.slice(0, 20)
      });
    })();
    """#

    private static let detailExtractionScriptTemplate = #"""
    (() => {
      const configuredSelectors = %%CNKI_SELECTORS%%;
      const selectorGroup = (name, fallback) => {
        const value = configuredSelectors?.[name];
        return Array.isArray(value) && value.length > 0 ? value : fallback;
      };
      const normalize = (value) => String(value || "").replace(/\s+/g, " ").trim();
      const unique = (values) => Array.from(new Set(values.filter(Boolean)));
      const rawPageText = String(document.body?.innerText || "");
      const pageText = normalize(rawPageText);
      const marker = normalize((document.title || "") + " " + pageText.slice(0, 1800));
      const isSuspiciousTitle = (value) => {
        const normalized = normalize(value);
        if (!normalized || normalized.length > 160) return true;
        const lowered = normalized.toLowerCase();
        const badTokens = ['cnki', '中国知网', 'network first', 'doi', 'journal', 'issn', 'online first'];
        const exactBadTitles = ['自动登录', '用户登录', '机构用户登录', '安全验证', '访问异常', '异常访问', '验证码'];
        if (badTokens.some((token) => lowered.includes(token))) return true;
        if (exactBadTitles.includes(normalized)) return true;
        if (normalized.length <= 12 && (normalized.includes('登录') || normalized.includes('验证'))) return true;
        if (lowered.startsWith('author') || lowered.startsWith('title')) return true;
        if (/^\d+$/.test(normalized)) return true;
        return false;
      };

      const metaValues = (names) => {
        const result = [];
        for (const name of names) {
          for (const el of Array.from(document.querySelectorAll(`meta[name="${name}"], meta[property="${name}"], meta[itemprop="${name}"]`))) {
            const value = normalize(el.getAttribute('content') || el.content || "");
            if (value) result.push(value);
          }
        }
        return Array.from(new Set(result));
      };

      const cleanAuthor = (value) => normalize(value)
        .replace(/[\d０-９¹²³⁴⁵⁶⁷⁸⁹]+$/g, '')
        .replace(/[\*†‡#]+$/g, '')
        .trim();
      const institutionLike = (value) => /大学|学院|研究所|研究院|管理局|水文局|实验室|中心|医院|部门|工程|水利部|出版社|编辑部|有限公司|股份有限公司|信息中心|勘测设计|研究院|集团|公司/.test(value);
      const authorNoiseLike = (value) => /印刷版|打印版|作者简介|基金资助|关键词|摘要|下载|引用|分享|收藏|导出|扫码|阅读|自动登录|安全验证|查看全文|AI/.test(value);
      const isLikelyAuthorToken = (value) => {
        const cleaned = cleanAuthor(value);
        if (!cleaned) return false;
        if (authorNoiseLike(cleaned) || institutionLike(cleaned) || isSuspiciousTitle(cleaned)) return false;
        return /^[\u3400-\u9FFF]{2,4}(?:·[\u3400-\u9FFF]{1,6})?$/.test(cleaned)
          || /^[A-Za-z][A-Za-z .'-]{1,60}$/.test(cleaned);
      };
      const parseAuthorTokens = (line) => unique(
        String(line || '')
          .split(/[，,；;、|]/)
          .flatMap((part) => part.split(/\s+/))
          .map(cleanAuthor)
          .filter(isLikelyAuthorToken)
      );
      const isLikelyAuthorLine = (line) => {
        const normalized = normalize(line);
        if (!normalized) return false;
        if (/摘要|关键词|基金资助|Abstract|Key words/i.test(normalized)) return false;
        const numberedMatches = Array.from(
          normalized.matchAll(/([\u3400-\u9FFF]{2,4}(?:·[\u3400-\u9FFF]{1,6})?)(?=\s*[0-9０-９¹²³⁴⁵⁶⁷⁸⁹])/g)
        )
          .map((match) => cleanAuthor(match[1]))
          .filter(isLikelyAuthorToken);
        if (numberedMatches.length >= 2) return true;

        const segments = normalized
          .split(/[，,；;、|\s]+/)
          .map(cleanAuthor)
          .filter(Boolean);
        if (segments.length >= 2 && segments.every(isLikelyAuthorToken)) {
          return true;
        }

        const parsed = parseAuthorTokens(normalized);
        return parsed.length >= 3;
      };

      const extractTitleFromContext = () => {
        const lines = rawPageText
          .replace(/\r/g, '')
          .split(/\n+/)
          .map(normalize)
          .filter(Boolean);

        const looksLikeAuthorLine = (line) =>
          /[\u3400-\u9FFF]{2,4}\s*[0-9０-９¹²³⁴⁵⁶⁷⁸⁹]/.test(line)
          && /[\u3400-\u9FFF]{2,4}\s*[0-9０-９¹²³⁴⁵⁶⁷⁸⁹].*[\u3400-\u9FFF]{2,4}\s*[0-9０-９¹²³⁴⁵⁶⁷⁸⁹]/.test(line);

        const badTitleTokens = /^(文献知网节|摘要|关键词|基金资助|专辑|专题|分类号|DOI|doi)/;

        for (let index = 0; index < lines.length; index += 1) {
          const line = lines[index];
          if (line.length < 6 || line.length > 80) continue;
          if (!/[\u3400-\u9FFF]/.test(line)) continue;
          if (badTitleTokens.test(line)) continue;
          if (isLikelyAuthorLine(line)) continue;
          if (/[0-9]{4}.*\([0-9]{2}\)|查看该刊数据库收录/.test(line)) continue;
          if (/[:：]/.test(line)) continue;

          const next = lines[index + 1] || '';
          const nextNext = lines[index + 2] || '';
          if (looksLikeAuthorLine(next) || /^(摘要|关键词)/.test(next) || /^(摘要|关键词)/.test(nextNext)) {
            return line;
          }
        }

        return "";
      };

      const collectTexts = (selectors, transform = normalize) => {
        const values = [];
        for (const selector of selectors) {
          for (const el of Array.from(document.querySelectorAll(selector))) {
            const text = transform(el.textContent || el.innerText || "");
            if (text) values.push(text);
          }
        }
        return unique(values);
      };

      const extractElementText = (el) => {
        if (!el) return "";
        const clone = el.cloneNode(true);
        for (const noise of Array.from(clone.querySelectorAll('sup, sub, script, style, [class*="tool"], [class*="btn"], [class*="icon"], [class*="operate"], [class*="action"], button'))) {
          noise.remove();
        }
        return normalize(clone.textContent || clone.innerText || "");
      };

      const firstText = (selectors) => {
        for (const selector of selectors) {
          for (const el of Array.from(document.querySelectorAll(selector))) {
            const text = extractElementText(el);
            if (text) return text;
          }
        }
        return "";
      };

      const pickBestTitle = (values) => {
        const normalizedValues = values.map(normalize).filter(Boolean);
        return normalizedValues.find((value) => !isSuspiciousTitle(value) && !isLikelyAuthorLine(value))
          || normalizedValues.find((value) => !isSuspiciousTitle(value))
          || "";
      };

      const isVisible = (el) => {
        if (!el) return false;
        const style = window.getComputedStyle(el);
        if (style.display === 'none' || style.visibility === 'hidden') return false;
        const rect = el.getBoundingClientRect();
        return rect.width > 0 && rect.height > 0;
      };

      const isToolbarLikeElement = (el) => {
        const hint = normalize(`${el?.className || ''} ${el?.id || ''} ${el?.getAttribute?.('role') || ''}`).toLowerCase();
        return /btn|tool|icon|operate|action|download|share|collect|quote|print|toolbar|menu|ai/.test(hint)
          || !!el?.closest?.('[class*="tool"], [class*="btn"], [class*="icon"], [class*="operate"], [class*="action"], button, .download, .share, .collect, .quote, .print');
      };

      const extractHeadingTitle = () => {
        const selectors = selectorGroup('detailTitle', [
          '.wx-tit > h1',
          '.xx_title > h1',
          '.title > h1',
          '.brief h1',
          'h1'
        ]);
        const candidates = Array.from(document.querySelectorAll(selectors.join(',')))
          .filter(isVisible)
          .map((el) => {
            const text = extractElementText(el);
            const rect = el.getBoundingClientRect();
            const fontSize = parseFloat(window.getComputedStyle(el).fontSize || '0') || 0;
            return { el, text, top: rect.top, fontSize };
          })
          .filter((item) => item.text && !isSuspiciousTitle(item.text) && !isLikelyAuthorLine(item.text))
          .sort((lhs, rhs) => rhs.fontSize - lhs.fontSize || lhs.top - rhs.top || lhs.text.length - rhs.text.length);
        return candidates[0]?.text || "";
      };

      const extractAuthorsNearTitle = (titleText) => {
        let windowText = rawPageText.replace(/\r/g, '');
        if (titleText) {
          const index = windowText.indexOf(titleText);
          if (index >= 0) {
            windowText = windowText.slice(index + titleText.length, index + titleText.length + 600);
          }
        }

        const stopTokens = ['摘要', 'Abstract', '关键词', 'Key words', '基金资助', '专辑', '专题'];
        let stopIndex = windowText.length;
        for (const token of stopTokens) {
          const index = windowText.indexOf(token);
          if (index >= 0) stopIndex = Math.min(stopIndex, index);
        }
        windowText = windowText.slice(0, stopIndex);
        const lines = windowText
          .split(/\n+/)
          .map(normalize)
          .filter(Boolean)
          .slice(0, 8);

        const looksLikeInstitutionLine = (line) =>
          /^(?:\d+[.．、]|[①②③④⑤⑥⑦⑧⑨⑩])/.test(line)
          || institutionLike(line);
        const looksLikeAuthorLine = (line) => {
          const numberedMatches = Array.from(
            line.matchAll(/([\u3400-\u9FFF]{2,4}(?:·[\u3400-\u9FFF]{1,6})?)(?=\s*[0-9０-９¹²³⁴⁵⁶⁷⁸⁹])/g)
          )
            .map((match) => cleanAuthor(match[1]))
            .filter(isLikelyAuthorToken);
          if (numberedMatches.length >= 2) return true;
          return parseAuthorTokens(line).length >= 2;
        };

        const authorLines = [];
        for (const line of lines) {
          if (authorNoiseLike(line) && !looksLikeAuthorLine(line)) continue;
          if (looksLikeInstitutionLine(line)) {
            if (authorLines.length > 0) break;
            continue;
          }
          if (looksLikeAuthorLine(line)) {
            authorLines.push(line);
            continue;
          }
          if (authorLines.length > 0) break;
        }

        const numberedChineseAuthors = authorLines.flatMap((line) =>
          Array.from(line.matchAll(/([\u3400-\u9FFF]{2,4}(?:·[\u3400-\u9FFF]{1,6})?)(?=\s*[0-9０-９¹²³⁴⁵⁶⁷⁸⁹])/g))
            .map((match) => cleanAuthor(match[1]))
            .filter(isLikelyAuthorToken)
        );
        if (numberedChineseAuthors.length > 0) {
          return unique(numberedChineseAuthors);
        }

        return unique(authorLines.flatMap(parseAuthorTokens));
      };

      const findTitleElement = (titleText) => {
        if (titleText) {
          const globalCandidates = Array.from(document.querySelectorAll('h1, h2, h3, div, p, span, strong'))
            .filter(isVisible)
            .map((el) => ({ el, text: extractElementText(el) }))
            .filter((item) =>
              item.text
              && !isSuspiciousTitle(item.text)
              && !isLikelyAuthorLine(item.text)
              && item.text.length <= Math.max(titleText.length + 24, 64)
              && (item.text === titleText || item.text.includes(titleText) || titleText.includes(item.text))
            )
            .sort((lhs, rhs) => {
              const lhsRect = lhs.el.getBoundingClientRect();
              const rhsRect = rhs.el.getBoundingClientRect();
              const lhsDelta = Math.abs(lhs.text.length - titleText.length);
              const rhsDelta = Math.abs(rhs.text.length - titleText.length);
              const lhsArea = lhsRect.width * lhsRect.height;
              const rhsArea = rhsRect.width * rhsRect.height;
              return lhsDelta - rhsDelta
                || lhsArea - rhsArea
                || lhsRect.top - rhsRect.top;
            });
          if (globalCandidates.length > 0) {
            return globalCandidates[0].el;
          }
        }

        const selectors = selectorGroup('detailTitle', [
          '.wx-tit > h1',
          '.xx_title > h1',
          '.title > h1',
          '.brief h1',
          'h1'
        ]);
        const candidates = Array.from(document.querySelectorAll(selectors.join(',')))
          .filter(isVisible)
          .map((el) => ({ el, text: extractElementText(el) }))
          .filter((item) => item.text && !isSuspiciousTitle(item.text) && !isLikelyAuthorLine(item.text));

        if (titleText) {
          const exact = candidates
            .filter((item) => item.text === titleText || item.text.includes(titleText) || titleText.includes(item.text))
            .sort((lhs, rhs) => lhs.text.length - rhs.text.length);
          if (exact.length > 0) {
            return exact[0].el;
          }
        }

        const byHeading = candidates
          .filter((item) => /^H[1-3]$/.test(item.el.tagName))
          .sort((lhs, rhs) => {
            const left = lhs.el.getBoundingClientRect();
            const right = rhs.el.getBoundingClientRect();
            return left.top - right.top || lhs.text.length - rhs.text.length;
          });
        return byHeading[0]?.el || candidates[0]?.el || null;
      };

      const extractAuthorsFromTitleRegion = (titleText) => {
        const titleElement = findTitleElement(titleText);
        if (!titleElement) return [];

        const titleRect = titleElement.getBoundingClientRect();
        const roots = [];
        const scopedRoot = titleElement.closest('.wx-tit, .xx_title, .title, .brief, .wxBaseinfo');
        if (scopedRoot) roots.push(scopedRoot);
        if (scopedRoot?.nextElementSibling) roots.push(scopedRoot.nextElementSibling);
        if (scopedRoot?.nextElementSibling?.nextElementSibling) roots.push(scopedRoot.nextElementSibling.nextElementSibling);
        roots.push(document.body);

        const evaluated = [];
        for (const root of roots) {
          const nodes = root === document.body
            ? Array.from(document.querySelectorAll('a, span, div, p, li'))
            : [root, ...Array.from(root.querySelectorAll('a, span, div, p, li'))];

          for (const el of nodes) {
            if (!isVisible(el) || el === titleElement || titleElement.contains(el) || isToolbarLikeElement(el)) continue;
            const rect = el.getBoundingClientRect();
            if (rect.top < titleRect.bottom - 8 || rect.top > titleRect.bottom + 140) continue;
            if (rect.right < titleRect.left - 40 || rect.left > titleRect.right + 120) continue;

            const nodeText = normalize(el.innerText || el.textContent || '');
            if (!nodeText || nodeText.length > 180) continue;
            if (/^(摘要|关键词|Abstract|Key words|基金资助|专辑|专题)/.test(nodeText)) continue;

            const nestedAuthors = unique(
              Array.from(el.querySelectorAll('a, span'))
                .flatMap((node) => parseAuthorTokens(node.innerText || node.textContent || ''))
            );
            const lineAuthors = parseAuthorTokens(nodeText);
            const authors = unique([...nestedAuthors, ...lineAuthors]);
            if (authors.length < 2) continue;

            evaluated.push({
              authors,
              top: rect.top,
              left: rect.left,
              width: rect.width,
              textLength: nodeText.length
            });
          }

          if (evaluated.length > 0 && root !== document.body) break;
        }

        evaluated.sort((lhs, rhs) =>
          rhs.authors.length - lhs.authors.length
          || Math.abs(lhs.top - titleRect.bottom) - Math.abs(rhs.top - titleRect.bottom)
          || Math.abs(lhs.left - titleRect.left) - Math.abs(rhs.left - titleRect.left)
          || lhs.textLength - rhs.textLength
        );

        return evaluated[0]?.authors || [];
      };

      const title = pickBestTitle([
        extractHeadingTitle(),
        ...metaValues(['citation_title', 'dc.title', 'DC.title']),
        firstText(selectorGroup('detailTitle', ['.wx-tit > h1', '.xx_title > h1', '.title > h1', '.brief h1', 'h1'])),
        extractTitleFromContext(),
      ]);
      const titleRegionAuthors = extractAuthorsFromTitleRegion(title);
      const contextualAuthors = titleRegionAuthors.length > 0 ? titleRegionAuthors : extractAuthorsNearTitle(title);
      const authorCandidates = [
        ...metaValues(['citation_author', 'dc.creator', 'DC.creator']).map(cleanAuthor),
        ...collectTexts(selectorGroup('detailAuthors', [
          '.author a',
          '.authors a',
          '.wx-tit .author a',
          '.wx-tit [class*="author"] a',
          '.author-list a',
          '#authorpart a',
          '.brief .author a',
          '.xx_title .author a'
        ]), cleanAuthor)
      ].filter(isLikelyAuthorToken);
      const authorBlock = firstText(selectorGroup('detailAuthorBlocks', [
        '.author',
        '.authors',
        '.wx-tit .author',
        '.wx-tit [class*="author"]',
        '.author-list',
        '#authorpart',
          '.brief .author',
          '.xx_title .author'
        ]));
      const blockAuthors = authorBlock ? parseAuthorTokens(authorBlock) : [];
      let authors = [];
      let authorSource = 'none';
      if (titleRegionAuthors.length > 0) {
        authors = titleRegionAuthors;
        authorSource = 'titleRegion';
      } else if (blockAuthors.length > 0) {
        authors = unique([...blockAuthors, ...authorCandidates]);
        authorSource = 'authorBlock';
      } else if (authorCandidates.length > 0) {
        authors = unique(authorCandidates);
        authorSource = 'metaOrLinks';
      } else if (contextualAuthors.length > 0) {
        authors = contextualAuthors;
        authorSource = 'contextual';
      } else {
        authors = [];
        authorSource = 'none';
      }
      const journal = metaValues(['citation_journal_title', 'citation_publication_title'])[0]
        || firstText(selectorGroup('detailJournal', ['.top-tip span a', '.wxBaseinfo .top-tip a', '.source a', '.source']));
      const doi = metaValues(['citation_doi', 'dc.identifier'])[0]
        || firstText(selectorGroup('detailDOI', ['.doi', '.wxBaseinfo .doi']));
      // 知网用 AbstractFilter() 把完整摘要存入隐藏 input#abstract_text，
      // 再把 #ChDivSummary 截断为短文本；必须优先读 #abstract_text.value。
      const cnkiFullAbstract = normalize(
        (document.getElementById('abstract_text')?.value || '').replace(/<[^>]+>/g, '')
      );
      const abstractText = cnkiFullAbstract
        || metaValues(['description', 'dc.description'])[0]
        || firstText(selectorGroup('detailAbstract', ['#ChDivSummary', '.summary', '.abstract', '.abstract-text', '.wxBaseinfo .abstract']));
      const volume = metaValues(['citation_volume'])[0] || "";
      const issue = metaValues(['citation_issue'])[0] || "";
      const firstPage = metaValues(['citation_firstpage'])[0] || "";
      const lastPage = metaValues(['citation_lastpage'])[0] || "";
      const yearText = metaValues(['citation_publication_date', 'citation_date'])[0]
        || firstText(selectorGroup('detailYearText', ['.top-tip', '.source', '.wxBaseinfo']));
      const hasVisibleVerificationUI = Array.from(document.querySelectorAll('input, iframe, img, div, span, p, a, button'))
        .filter(isVisible)
        .some((el) => {
          const text = normalize(el.innerText || el.textContent || "");
          const hint = normalize(`${el.className || ''} ${el.id || ''} ${el.getAttribute?.('placeholder') || ''} ${el.getAttribute?.('aria-label') || ''}`).toLowerCase();
          return (!!text && text.length <= 120 && /安全验证|请完成验证|验证码|访问异常|异常访问|验证后继续访问/.test(text))
            || /(captcha|validate)/.test(hint);
        });
      const hasVisibleDetailScaffold = !!title && (authors.length > 0 || !!abstractText || !!journal || !!doi);
      const blockedSignals = /安全验证|请完成验证|验证码|访问异常|异常访问|验证后继续访问/.test(marker)
        || hasVisibleVerificationUI;
      const blockedReason = blockedSignals ? (hasVisibleVerificationUI ? 'verification-ui' : 'verification-marker') : null;
      const blocked = blockedSignals && !hasVisibleDetailScaffold;

      return JSON.stringify({
        blocked,
        blockedReason,
        title: title || null,
        authors,
        authorSource,
        journal: journal || null,
        doi: doi || null,
        abstract: abstractText || null,
        volume: volume || null,
        issue: issue || null,
        firstPage: firstPage || null,
        lastPage: lastPage || null,
        yearText: yearText || null,
        bodyText: pageText.slice(0, 12000),
        url: location.href
      });
    })();
    """#
}
