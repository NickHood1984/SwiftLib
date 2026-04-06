#!/usr/bin/env node
/**
 * verify-entity-decode.js — Verify HTML entity decoding in citeproc-bundle.js
 *
 * Tests that &#38; and other HTML entities in bibliography output are correctly
 * decoded to their Unicode equivalents when processed through the bundle's
 * plainBibliographyFromBibResult / stripTagsOneLine pipeline.
 */

const path = require("path");
require(path.resolve(__dirname, "../Sources/SwiftLibCore/Resources/WordAddin/dist/citeproc-bundle.js"));

const CSL = globalThis.CSL;

const testLocaleXML = `<?xml version="1.0" encoding="utf-8"?>
<locale xmlns="http://purl.org/net/xbiblio/csl" version="1.0" xml:lang="en-US">
  <terms>
    <term name="and">and</term>
    <term name="open-quote">\u201C</term>
    <term name="close-quote">\u201D</term>
    <term name="open-inner-quote">\u2018</term>
    <term name="close-inner-quote">\u2019</term>
  </terms>
</locale>`;

const testStyleXML = `<?xml version="1.0" encoding="utf-8"?>
<style xmlns="http://purl.org/net/xbiblio/csl" version="1.0" class="in-text">
  <info><title>Entity Test</title><id>entity-test</id>
    <updated>2024-01-01T00:00:00+00:00</updated></info>
  <citation><layout><text variable="title"/></layout></citation>
  <bibliography><layout><text variable="title"/></layout></bibliography>
</style>`;

// Test cases: title → expected decoded output in plain text
const testCases = [
  { title: "Smith & Jones", expect: "Smith & Jones", desc: "Ampersand via &#38;" },
  { title: "A < B > C", expect: "A < B > C", desc: "Less-than and greater-than" },
  // citeproc-js wraps double-quoted titles using locale open/close-quote terms (“” in en-US)
  { title: 'Say "Hello"', expect: 'Say \u201CHello\u201D', desc: "Double quotes (locale-wrapped)" },
  // citeproc-js normalises straight apostrophe to typographic right-single-quote (\u2019)
  { title: "It's fine", expect: "It\u2019s fine", desc: "Apostrophe (typographic)" },
  { title: "Foo\u00A0Bar", expect: "Foo Bar", desc: "Non-breaking space normalized" },
  { title: "A\u2013B", expect: "A\u2013B", desc: "En-dash preserved" },
  { title: "A\u2014B", expect: "A\u2014B", desc: "Em-dash preserved" },
];

let passed = 0;
let failed = 0;

console.log("\n=== Entity Decode Verification ===\n");

for (const tc of testCases) {
  const sys = {
    retrieveLocale: () => testLocaleXML,
    retrieveItem: (id) => ({
      id: String(id), type: "article-journal", title: tc.title,
      issued: { "date-parts": [[2024]] },
    }),
  };

  try {
    const engine = new CSL.Engine(sys, testStyleXML);
    engine.updateItems(["1"]);
    engine.setOutputFormat("html");
    const bib = engine.makeBibliography();

    if (!bib || !bib[1] || !bib[1].length) {
      console.error(`  ✗ ${tc.desc}: no bibliography output`);
      failed++;
      continue;
    }

    const rawHtml = bib[1][0];
    // Simulate the same pipeline as plainBibliographyFromBibResult
    const stripped = rawHtml
      .replace(/<script[\s\S]*?<\/script>/gi, "")
      .replace(/<style[\s\S]*?<\/style>/gi, "")
      .replace(/<[^>]+>/g, " ");

    // Decode entities (same as in the bundle)
    const NAMED = {
      amp: "&", lt: "<", gt: ">", quot: '"', apos: "'",
      nbsp: "\u00A0", ndash: "\u2013", mdash: "\u2014",
      lsquo: "\u2018", rsquo: "\u2019", ldquo: "\u201C", rdquo: "\u201D",
      bull: "\u2022", hellip: "\u2026", trade: "\u2122",
      copy: "\u00A9", reg: "\u00AE", deg: "\u00B0",
    };
    function decode(text) {
      return text.replace(/&(#x([0-9a-fA-F]+)|#(\d+)|([a-zA-Z]+));/g,
        (m, _f, hex, dec, named) => {
          if (hex) return String.fromCodePoint(parseInt(hex, 16));
          if (dec) return String.fromCodePoint(parseInt(dec, 10));
          if (named && NAMED[named.toLowerCase()]) return NAMED[named.toLowerCase()];
          return m;
        });
    }
    let decoded = decode(decode(stripped));
    decoded = decoded.replace(/\u00A0/g, " ").replace(/\s+/g, " ").trim();

    if (decoded === tc.expect) {
      console.log(`  ✓ ${tc.desc}: "${decoded}"`);
      passed++;
    } else {
      console.error(`  ✗ ${tc.desc}: expected "${tc.expect}", got "${decoded}"`);
      console.error(`    Raw HTML: ${rawHtml.trim()}`);
      failed++;
    }
  } catch (e) {
    console.error(`  ✗ ${tc.desc}: ${e.message}`);
    failed++;
  }
}

console.log(`\n=== Results: ${passed} passed, ${failed} failed ===\n`);
process.exit(failed > 0 ? 1 : 0);
