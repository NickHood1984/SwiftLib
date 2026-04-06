/* global Word, Office */
/**
 * U+200C placed after citation CC (outside control) — remove before unwrap / empty-shell delete.
 * @param {Word.RequestContext} ctx
 * @param {Word.ContentControl} citationCC
 */
globalThis.swiftLibTryDeleteLightweightGuardAfterCitationCC = async function (ctx, citationCC) {
  if (typeof Word === "undefined" || !citationCC || !ctx) return;
  try {
    const afterLoc =
      typeof Word.RangeLocation !== "undefined" && Word.RangeLocation.after !== undefined
        ? Word.RangeLocation.after
        : "After";
    const tail = citationCC.getRange(afterLoc);
    if (typeof tail.getNextTextRange !== "function") return;
    const unit =
      typeof Word.MovementUnit !== "undefined" && Word.MovementUnit.character !== undefined
        ? Word.MovementUnit.character
        : "Character";
    const guardRange = tail.getNextTextRange(unit, false);
    if (!guardRange) return;
    guardRange.load("text");
    await ctx.sync();
    const t = guardRange.text || "";
    if (t !== "\u200C") return;
    guardRange.delete();
    await ctx.sync();
  } catch (e) {
    console.warn("SwiftLib swiftLibTryDeleteLightweightGuardAfterCitationCC:", e);
  }
};

/** Loaded in one batch from Paragraph.font; applied to insertion point after ZWSP. */
const SWIFTLIB_FONT_COPY_KEYS = [
  "bold",
  "italic",
  "name",
  "nameAscii",
  "nameFarEast",
  "nameOther",
  "size",
  "sizeBidirectional",
  "color",
  "underline",
  "underlineColor",
  "subscript",
  "superscript",
  "strikeThrough",
  "doubleStrikeThrough",
  "smallCaps",
  "allCaps",
  "highlightColor",
  "spacing",
  "position",
  "scaling",
];

const SWIFTLIB_FONT_LOAD_SPEC = SWIFTLIB_FONT_COPY_KEYS.join(",");

function swiftLibCopyLoadedFontToTypingPoint(srcFont, dstFont) {
  if (!srcFont || !dstFont) return;
  for (const k of SWIFTLIB_FONT_COPY_KEYS) {
    try {
      const v = srcFont[k];
      if (v !== undefined && v !== null && typeof v !== "object") {
        dstFont[k] = v;
      }
    } catch (_) {
      /* host may reject some keys */
    }
  }
  try {
    dstFont.hidden = false;
  } catch (_) {
    /* ignore */
  }
}

async function swiftLibGetParagraphFontForCitation(ctx, citationCC) {
  const locStart =
    typeof Word.RangeLocation !== "undefined" && Word.RangeLocation.start !== undefined
      ? Word.RangeLocation.start
      : "Start";
  const ccStart = citationCC.getRange(locStart);
  const para = ccStart.paragraphs.getFirst();
  para.font.load(SWIFTLIB_FONT_LOAD_SPEC);
  await ctx.sync();
  return para.font;
}

globalThis.swiftLibApplyParagraphFontFromCitation = async function (ctx, citationCC, dstFont) {
  if (typeof Word === "undefined" || !ctx || !citationCC || !dstFont) return;
  const paraFont = await swiftLibGetParagraphFontForCitation(ctx, citationCC);
  swiftLibCopyLoadedFontToTypingPoint(paraFont, dstFont);
  try {
    dstFont.hidden = false;
    dstFont.subscript = false;
    dstFont.superscript = false;
  } catch (_) {
    /* ignore */
  }
};

/**
 * Match typing after citation to the surrounding paragraph style.
 * This intentionally avoids inheriting mixed inline character formatting from the pre-citation text.
 * @param {Word.RequestContext} ctx
 * @param {Word.ContentControl} citationCC
 * @param {Word.Range} typingRange collapsed range after ZWSP
 */
globalThis.swiftLibSyncTypingFormatAfterCitationGuard = async function (ctx, citationCC, typingRange) {
  if (typeof Word === "undefined" || !citationCC || !typingRange || !typingRange.font || !ctx) return;

  try {
    await globalThis.swiftLibApplyParagraphFontFromCitation(ctx, citationCC, typingRange.font);
    await ctx.sync();
  } catch (e) {
    console.warn("SwiftLib swiftLibSyncTypingFormatAfterCitationGuard:", e);
    try {
      typingRange.font.hidden = false;
      typingRange.font.subscript = false;
      typingRange.font.superscript = false;
      if (
        typeof Office !== "undefined" &&
        Office.context &&
        Office.context.requirements &&
        Office.context.requirements.isSetSupported("WordApiDesktop", "1.3") &&
        typeof typingRange.font.reset === "function"
      ) {
        typingRange.font.reset();
      }
    } catch (_) {
      /* ignore */
    }
  }
};
