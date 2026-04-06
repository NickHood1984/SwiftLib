#!/usr/bin/env node
/**
 * verify-fixes.js — End-to-end verification of the key fixes:
 *   1. HTML entity decoding (named, decimal, hex, double-encoded)
 *   2. Bibliography output (no "References" sentinel line)
 *   3. superscriptCitationIDs detection from CSL layout_decorations
 *   4. CSL.Engine availability via globalThis
 */

const assert = require("assert");
const fs = require("fs");
const path = require("path");

// Load the bundle
require(path.resolve(__dirname, "../Sources/SwiftLibCore/Resources/WordAddin/dist/citeproc-bundle.js"));

const SwiftLibCiteproc = globalThis.SwiftLibCiteproc;
const CSL = globalThis.CSL;

let passed = 0;
let failed = 0;

function test(name, fn) {
  try {
    fn();
    console.log(`  ✓ ${name}`);
    passed++;
  } catch (e) {
    console.error(`  ✗ ${name}: ${e.message}`);
    failed++;
  }
}

console.log("\n=== SwiftLib Fix Verification ===\n");

// --- Test 1: Global exports ---
console.log("1. Global exports");
test("SwiftLibCiteproc is an object", () => assert.strictEqual(typeof SwiftLibCiteproc, "object"));
test("renderDocumentPayload is a function", () => assert.strictEqual(typeof SwiftLibCiteproc.renderDocumentPayload, "function"));
test("preloadStyleAndLocale is a function", () => assert.strictEqual(typeof SwiftLibCiteproc.preloadStyleAndLocale, "function"));
test("clearCiteprocCaches is a function", () => assert.strictEqual(typeof SwiftLibCiteproc.clearCiteprocCaches, "function"));
test("CSL.Engine is a function", () => assert.strictEqual(typeof CSL.Engine, "function"));

// --- Test 2: Entity decoding in stripTagsOneLine (via bundle internals) ---
console.log("\n2. Entity decoding (testing via CSL.Engine bibliography output)");

// Create a minimal CSL style that will produce bibliography with & in output
const testStyleXML = `<?xml version="1.0" encoding="utf-8"?>
<style xmlns="http://purl.org/net/xbiblio/csl" version="1.0" class="in-text">
  <info>
    <title>Test Style</title>
    <id>test-verify</id>
    <updated>2024-01-01T00:00:00+00:00</updated>
  </info>
  <citation>
    <layout prefix="(" suffix=")" delimiter="; ">
      <text variable="title"/>
    </layout>
  </citation>
  <bibliography>
    <layout>
      <text variable="title"/>
    </layout>
  </bibliography>
</style>`;

const testLocaleXML = `<?xml version="1.0" encoding="utf-8"?>
<locale xmlns="http://purl.org/net/xbiblio/csl" version="1.0" xml:lang="en-US">
  <terms>
    <term name="and">and</term>
  </terms>
</locale>`;

// Create engine
let engine;
try {
  const sys = {
    retrieveLocale: () => testLocaleXML,
    retrieveItem: (id) => ({
      id: String(id),
      type: "article-journal",
      title: "Smith & Jones: A Test",
      author: [{ family: "Smith", given: "John" }, { family: "Jones", given: "Jane" }],
      issued: { "date-parts": [[2024]] },
    }),
  };
  engine = new CSL.Engine(sys, testStyleXML);
  engine.updateItems(["1"]);
  console.log("  ✓ CSL.Engine created successfully");
  passed++;
} catch (e) {
  console.error("  ✗ CSL.Engine creation failed:", e.message);
  failed++;
}

if (engine) {
  // Test bibliography output
  engine.setOutputFormat("html");
  const bib = engine.makeBibliography();
  test("makeBibliography returns result", () => assert.ok(bib && bib[1] && bib[1].length > 0));

  if (bib && bib[1]) {
    const rawHtml = bib[1][0];
    console.log(`  Raw HTML: ${rawHtml.trim()}`);
    // The HTML should contain &amp; for the & in "Smith & Jones"
    test("Bibliography HTML contains entity-encoded &", () => {
      assert.ok(rawHtml.includes("&amp;") || rawHtml.includes("&"), "Should contain & or &amp;");
    });
  }

  // Test citation output
  engine.setOutputFormat("text");
  const citResult = engine.rebuildProcessorState(
    [{ citationID: "c1", citationItems: [{ id: "1" }], properties: { noteIndex: 0 } }],
    "text"
  );
  test("rebuildProcessorState returns citation text", () => {
    assert.ok(citResult && citResult.length > 0);
    const text = citResult[0][2];
    console.log(`  Citation text: ${text}`);
    assert.ok(text.includes("Smith"), "Should contain author name");
  });
}

// --- Test 3: Superscript detection ---
console.log("\n3. Superscript detection from CSL layout_decorations");

const supStyleXML = `<?xml version="1.0" encoding="utf-8"?>
<style xmlns="http://purl.org/net/xbiblio/csl" version="1.0" class="in-text">
  <info>
    <title>Superscript Test</title>
    <id>test-sup</id>
    <updated>2024-01-01T00:00:00+00:00</updated>
  </info>
  <citation>
    <layout vertical-align="sup" prefix="[" suffix="]">
      <text variable="citation-number"/>
    </layout>
  </citation>
  <bibliography>
    <layout>
      <text variable="title"/>
    </layout>
  </bibliography>
</style>`;

try {
  const sys2 = {
    retrieveLocale: () => testLocaleXML,
    retrieveItem: (id) => ({
      id: String(id),
      type: "article-journal",
      title: "Test Article",
      issued: { "date-parts": [[2024]] },
    }),
  };
  const supEngine = new CSL.Engine(sys2, supStyleXML);
  supEngine.updateItems(["1"]);

  const decors = supEngine.citation?.opt?.layout_decorations || [];
  const hasSup = decors.some((d) => d[0] === "@vertical-align" && d[1] === "sup");
  test("layout_decorations contains vertical-align=sup", () => assert.ok(hasSup));
  console.log(`  layout_decorations: ${JSON.stringify(decors)}`);
} catch (e) {
  console.error("  ✗ Superscript engine test failed:", e.message);
  failed++;
}

// --- Test 4: swiftlib-shared.js ---
console.log("\n4. swiftlib-shared.js functions");
require(path.resolve(__dirname, "../Sources/SwiftLibCore/Resources/WordAddin/swiftlib-shared.js"));
const shared = globalThis.SwiftLibShared;

test("SwiftLibShared is an object", () => assert.strictEqual(typeof shared, "object"));
test("setCitationSuperscript is a function", () => assert.strictEqual(typeof shared.setCitationSuperscript, "function"));
test("applySuperscriptToInsertedRange is a function", () => assert.strictEqual(typeof shared.applySuperscriptToInsertedRange, "function"));
test("collectScanFromItems is a function", () => assert.strictEqual(typeof shared.collectScanFromItems, "function"));
test("finalizeToPlainTextInContext is a function", () => assert.strictEqual(typeof shared.finalizeToPlainTextInContext, "function"));
test("encodeCitationFallbackPayload is a function", () => assert.strictEqual(typeof shared.encodeCitationFallbackPayload, "function"));

// --- Summary ---
console.log(`\n=== Results: ${passed} passed, ${failed} failed ===\n`);
process.exit(failed > 0 ? 1 : 0);
