/* global Word */
(function (global) {
  const shared = global.SwiftLibShared || (global.SwiftLibShared = {});
  const FALLBACK_PREFIX = "swiftlib:v3:payload:";

  shared.runtimeLocks = global.__swiftLibRuntimeLocks || (global.__swiftLibRuntimeLocks = {
    upsertCitation: false,
  });

  function parseIds(csv) {
    return String(csv || "")
      .split(",")
      .map(Number)
      .filter(Number.isInteger);
  }

  function encodeCitationFallbackPayload(style, ids) {
    if (!Array.isArray(ids) || !ids.length) return "";
    return `${FALLBACK_PREFIX}${encodeURIComponent(style || "")}:${ids.join(",")}`;
  }

  function decodeCitationFallbackPayload(raw) {
    if (!raw || !raw.startsWith(FALLBACK_PREFIX)) return null;
    const rest = raw.substring(FALLBACK_PREFIX.length);
    const splitAt = rest.indexOf(":");
    if (splitAt < 0) return null;
    const style = decodeURIComponent(rest.substring(0, splitAt));
    const ids = parseIds(rest.substring(splitAt + 1));
    if (!ids.length) return null;
    return { style, ids };
  }

  function trySetCitationFallbackPlaceholder(cc, style, ids) {
    try {
      cc.placeholderText = encodeCitationFallbackPayload(style, ids);
    } catch {
      /* ignore */
    }
  }

  function parseCitationTag(tag, citePrefix) {
    if (!tag || !tag.startsWith(citePrefix)) return null;
    const rest = tag.substring(citePrefix.length);
    if (!rest.includes(":")) {
      const id = rest.toLowerCase();
      if (/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id)) {
        return { kind: "citation", id, style: "", ids: [], fromShortTag: true };
      }
      return null;
    }
    const parts = rest.split(":");
    if (parts.length < 3) return null;
    const id = parts[0].toLowerCase();
    const style = decodeURIComponent(parts[1]);
    const ids = parseIds(parts[2]);
    if (!ids.length) return null;
    return { kind: "citation", id, style, ids, fromShortTag: false };
  }

  function parseBibliographyTag(tag, bibPrefix) {
    if (!tag || !tag.startsWith(bibPrefix)) return null;
    const rest = tag.substring(bibPrefix.length);
    const parts = rest.split(":");
    if (parts.length < 2) return null;
    return { kind: "bibliography", id: parts[0].toLowerCase(), style: decodeURIComponent(parts[1]) };
  }

  function parseTag(tag, citePrefix, bibPrefix) {
    return parseCitationTag(tag, citePrefix) || parseBibliographyTag(tag, bibPrefix);
  }

  function makeCitationTag(citePrefix, id, style, ids) {
    return `${citePrefix}${id}:${encodeURIComponent(style)}:${ids.join(",")}`;
  }

  function chooseCitationContentTag(citePrefix, maxWordTagLength, citationID, style, ids) {
    const full = makeCitationTag(citePrefix, citationID, style, ids);
    if (full.length <= maxWordTagLength) return { tag: full, isShort: false };
    return { tag: `${citePrefix}${citationID}`, isShort: true };
  }

  function makeBibliographyTag(bibPrefix, id, style) {
    return `${bibPrefix}${id}:${encodeURIComponent(style)}`;
  }

  function getUnderlineOnValue() {
    try {
      if (typeof Word !== "undefined" && Word.UnderlineType && Word.UnderlineType.single !== undefined) {
        return Word.UnderlineType.single;
      }
    } catch {
      /* ignore */
    }
    return "Single";
  }

  function getUnderlineOffValue() {
    try {
      if (typeof Word !== "undefined" && Word.UnderlineType && Word.UnderlineType.none !== undefined) {
        return Word.UnderlineType.none;
      }
    } catch {
      /* ignore */
    }
    return "None";
  }

  function applyCitationFormattingToFont(font, formatting) {
    if (!font || !formatting) return;
    try {
      if (formatting.bold != null) font.bold = !!formatting.bold;
    } catch {
      /* ignore */
    }
    try {
      if (formatting.italic != null) font.italic = !!formatting.italic;
    } catch {
      /* ignore */
    }
    try {
      if (formatting.underline != null) {
        font.underline = formatting.underline ? getUnderlineOnValue() : getUnderlineOffValue();
      }
    } catch {
      /* ignore */
    }
    try {
      if (formatting.smallCaps != null) font.smallCaps = !!formatting.smallCaps;
    } catch {
      /* ignore */
    }
    try {
      // Word treats superscript / subscript as mutually exclusive vertical-align states.
      // On Mac, writing `subscript = false` immediately after `superscript = true`
      // can snap the text back to baseline. Apply the opposite-off switch first,
      // then set the active state last.
      if (formatting.superscript === true) {
        try { font.subscript = false; } catch {}
        font.superscript = true;
      } else if (formatting.subscript === true) {
        try { font.superscript = false; } catch {}
        font.subscript = true;
      } else {
        if (formatting.superscript != null) font.superscript = !!formatting.superscript;
        if (formatting.subscript != null) font.subscript = !!formatting.subscript;
      }
    } catch {
      /* ignore */
    }
  }

  /**
   * Apply citation formatting to a content control.
   *
   * Two-layer approach to ensure the format sticks in Word:
   *   1. cc.font (ContentControl-level font)
   *   2. cc.getRange().font (fresh Range-level font — most reliable;
   *      a new getRange() call after ctx.sync() returns a live reference
   *      that is not stale, unlike the Range returned by insertText() before sync).
   *
   * NOTE: Always call this AFTER ctx.sync() so that the CC's content has
   * already been committed and cc.getRange() returns a fresh, stable reference.
   * The insertedRange returned by insertText() before sync can become stale
   * on Word for Mac and silently drop superscript; using getRange() post-sync
   * is the reliable path.
   */
  function setCitationFormatting(cc, formatting) {
    if (!cc || !formatting) return;
    // Layer 1: ContentControl font
    try {
      applyCitationFormattingToFont(cc.font, formatting);
    } catch {
      /* ignore */
    }
    // Layer 2: Fresh content range font (post-sync stable reference — most reliable for superscript)
    try {
      const contentLoc =
        typeof Word !== "undefined" && Word.RangeLocation && Word.RangeLocation.content !== undefined
          ? Word.RangeLocation.content
          : "Content";
      const contentRange = cc.getRange(contentLoc);
      applyCitationFormattingToFont(contentRange.font, formatting);
    } catch {
      /* ignore */
    }
    // Layer 3: Whole control range fallback for older / inconsistent hosts.
    try {
      const wholeRange = cc.getRange();
      applyCitationFormattingToFont(wholeRange.font, formatting);
    } catch {
      /* ignore */
    }
  }

  function setCitationSuperscript(cc, enabled) {
    setCitationFormatting(cc, {
      superscript: !!enabled,
      subscript: false,
    });
  }

  /**
   * Apply citation formatting to a Range returned by insertText().
   * Call this immediately after cc.insertText(text, loc) in the same
   * Word.run context for the most reliable formatting.
   *
   * @param {Word.Range} insertedRange — the Range returned by insertText()
   * @param {object | null} formatting
   */
  function applyCitationFormattingToInsertedRange(insertedRange, formatting) {
    if (!insertedRange || !insertedRange.font) return;
    try {
      applyCitationFormattingToFont(insertedRange.font, formatting);
    } catch {
      /* ignore */
    }
  }

  function applySuperscriptToInsertedRange(insertedRange, enabled) {
    applyCitationFormattingToInsertedRange(insertedRange, {
      superscript: !!enabled,
      subscript: false,
    });
  }

  function escapeHtml(text) {
    return String(text || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

  function citationHtmlFromTextAndFormatting(text, formatting) {
    if (text == null) return null;
    if (!formatting || !Object.values(formatting).some((value) => value === true)) return null;

    let html = escapeHtml(text);
    if (formatting.smallCaps === true) {
      html = `<span style="font-variant: small-caps;">${html}</span>`;
    }
    if (formatting.underline === true) {
      html = `<u>${html}</u>`;
    }
    if (formatting.italic === true) {
      html = `<i>${html}</i>`;
    }
    if (formatting.bold === true) {
      html = `<b>${html}</b>`;
    }
    if (formatting.superscript === true) {
      html = `<sup>${html}</sup>`;
    } else if (formatting.subscript === true) {
      html = `<sub>${html}</sub>`;
    }
    return html;
  }

  function collectScanFromItems(items, snapMap, options) {
    const map = snapMap || new Map();
    const citations = [];
    const bibControls = [];
    let position = 0;

    for (const cc of items) {
      const tag = cc.tag || "";
      if (!tag.startsWith(options.tagPrefix)) continue;
      const parsed = options.parseTag(tag);
      if (!parsed) continue;

      if (parsed.kind === "citation") {
        let style = parsed.style;
        let ids = parsed.ids?.length ? parsed.ids.slice() : [];

        let citationItems = null;

        if (parsed.fromShortTag || !ids.length) {
          const fallback = options.readFallbackPayload ? options.readFallbackPayload(cc) : null;
          if (fallback) {
            style = fallback.style || style || "";
            ids = fallback.ids?.length ? fallback.ids.slice() : ids;
          }
        }

        if ((parsed.fromShortTag || !ids.length) && !ids.length) {
          const row = map.get(parsed.id);
          if (row) {
            style = row.style || style || "";
            ids = row.ids?.length ? row.ids.slice() : ids;
            // v4: restore rich citation item options (locator/prefix/suffix/suppressAuthor)
            if (Array.isArray(row.citationItems)) citationItems = row.citationItems;
          }
        } else {
          // Even when ids are available from the tag, still restore citationItems from snapMap
          const row = map.get(parsed.id);
          if (row && Array.isArray(row.citationItems)) citationItems = row.citationItems;
        }

        if (!ids.length) continue;
        citations.push({
          citationID: parsed.id,
          ids,
          style,
          position: position++,
          isShortTag: parsed.fromShortTag === true,
          // v4: rich item options; null means use plain refIds without options
          citationItems,
        });
      } else if (parsed.kind === "bibliography") {
        bibControls.push({ ccId: cc.id });
      }
    }

    return { citations, bibControls };
  }

  async function finalizeToPlainTextInContext(ctx, options) {
    const locReplace =
      typeof Word !== "undefined" && Word.InsertLocation && Word.InsertLocation.replace !== undefined
        ? Word.InsertLocation.replace
        : "Replace";

    const controls = ctx.document.contentControls;
    controls.load("items");
    await ctx.sync();

    const pairs = [];
    for (const cc of controls.items) {
      cc.load("tag,id");
      const rng = cc.getRange();
      rng.load("text,start");
      pairs.push({ cc, rng });
    }
    await ctx.sync();

    const targets = pairs.filter(({ cc }) => {
      const tag = cc.tag || "";
      return (
        tag.startsWith(options.citeTagPrefix) ||
        tag.startsWith(options.bibTagPrefix) ||
        options.isBoundaryGuardTag(tag)
      );
    });
    targets.sort((a, b) => (b.rng.start ?? 0) - (a.rng.start ?? 0));

    for (const { cc, rng } of targets) {
      const tag = cc.tag || "";
      if (options.isBoundaryGuardTag(tag)) {
        cc.delete(true);
        continue;
      }
      if (tag.startsWith(options.citeTagPrefix) && typeof options.deleteLightweightGuardAfterCitationCC === "function") {
        await options.deleteLightweightGuardAfterCitationCC(ctx, cc);
      }
      const plain = rng.text || "";
      rng.insertText(plain, locReplace);
      cc.delete(false);
    }
    await ctx.sync();

    if (options.isWordApi14()) {
      const parts = ctx.document.customXmlParts;
      parts.load("items");
      await ctx.sync();
      for (const p of parts.items) p.load("namespaceUri");
      await ctx.sync();
      for (let i = parts.items.length - 1; i >= 0; i--) {
        if (parts.items[i].namespaceUri === options.xmlNamespace) {
          parts.items[i].delete();
        }
      }
      await ctx.sync();
    }
  }

  shared.encodeCitationFallbackPayload = encodeCitationFallbackPayload;
  shared.decodeCitationFallbackPayload = decodeCitationFallbackPayload;
  shared.trySetCitationFallbackPlaceholder = trySetCitationFallbackPlaceholder;
  shared.parseCitationTag = parseCitationTag;
  shared.parseBibliographyTag = parseBibliographyTag;
  shared.parseTag = parseTag;
  shared.makeCitationTag = makeCitationTag;
  shared.chooseCitationContentTag = chooseCitationContentTag;
  shared.makeBibliographyTag = makeBibliographyTag;
  shared.setCitationFormatting = setCitationFormatting;
  shared.setCitationSuperscript = setCitationSuperscript;
  shared.applyCitationFormattingToInsertedRange = applyCitationFormattingToInsertedRange;
  shared.applySuperscriptToInsertedRange = applySuperscriptToInsertedRange;
  shared.citationHtmlFromTextAndFormatting = citationHtmlFromTextAndFormatting;
  shared.collectScanFromItems = collectScanFromItems;
  shared.finalizeToPlainTextInContext = finalizeToPlainTextInContext;
})(globalThis);
