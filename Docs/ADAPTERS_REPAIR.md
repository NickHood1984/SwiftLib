# Adapter Repair Playbook (for AI agents)

> **Audience**: This file is the primary input for an AI agent (Warp Cloud Agent, Claude Code, etc.) tasked with repairing a drifted adapter. Follow it literally. Humans should read `ADAPTERS.md` first for context; this file trades narrative for determinism.

---

## 0. Ground rules (read first, do not violate)

1. **You may only edit**: files under `Sources/SwiftLibCore/Resources/adapters/*.json`. That is the entire hot-patch surface.
2. **You may NOT edit**: `SiteAdapterRuntime.swift`, `SiteAdapterDefinition.swift`, `SiteAdapterRegistry.swift`, `MetadataFetcher.swift`, or any other Swift source. If a fix requires a new transform / postProcess / route.kind / extract.kind that isn't in `Docs/adapter-schema.json`, **stop and open a human-labeled issue** describing the missing capability.
3. **You may NOT invent values**. Valid enum values are enumerated in `Docs/adapter-schema.json`. Inventing a `"transform": "myNewThing"` silently returns the input unchanged — the tests pass but the output is wrong.
4. **You may NOT delete old fallback paths** when adding new ones. Old upstreams sometimes revert. Append, don't replace.
5. **Verify empirically**. Never commit a patch that hasn't been confirmed by live canary (`./scripts/canary.sh`).
6. **Bump `schemaVersion`** on every commit that changes any adapter JSON.

---

## 1. Inputs you will receive

When invoked (e.g. via a failing canary CI workflow), you get:

| Variable | Example | Source |
|---|---|---|
| `$ADAPTER_ID` | `openalex-work` | From the failing canary name |
| `$CANARY_NAME` | `"Deep learning (10.1038/nature14539) — byDoi"` | From the failing canary case |
| `$ROUTE_NAME` | `byDoi` | From `canary[].route` |
| `$CONTEXT` | `{"doi": "10.1038/nature14539"}` | From `canary[].context` |
| `$EXPECTED` | `{"journal": "Nature", "year": "2015", ...}` | From `canary[].expectSearch` |
| `$ACTUAL` | `{"journal": "Nature", "year": null, ...}` | Harness output |
| `$ASSERTION` | `"search.year mismatch (actual=nil)"` | XCTest message |

You also have read access to:
- `Sources/SwiftLibCore/Resources/adapters/$ADAPTER_ID.json` (the drifted file)
- `Docs/adapter-schema.json` (allowed syntax)
- A shell with `curl` (to pull ground-truth responses)

---

## 2. Deterministic repair steps

### Step 2.1 — Reproduce the failure

```bash
./scripts/canary.sh
```

Confirm `$ADAPTER_ID` fails with `$ASSERTION`. If it passes now, the issue self-resolved; close with a note and exit.

### Step 2.2 — Load both the adapter and the live response

```bash
# Read current adapter
cat Sources/SwiftLibCore/Resources/adapters/$ADAPTER_ID.json

# Reproduce the live URL. Substitute $CONTEXT values into the route's url template.
# For OpenAlex example:
curl -sS "https://api.openalex.org/works/doi:10.1038/nature14539?select=...&mailto=" \
  | python3 -m json.tool > /tmp/actual.json
```

### Step 2.3 — Diff

For EACH field in `$EXPECTED` where `$ACTUAL[field]` is null or wrong:

1. Locate the field definition in the adapter JSON: `routes[$ROUTE_NAME].extract.fields[<fieldName>]`
2. Walk each `paths[i]` against the live response manually:
   ```bash
   python3 -c "import json; d=json.load(open('/tmp/actual.json')); print(d['publication_year'])"
   ```
3. Classify the root cause:
   - **Case A — Field renamed**: the old path returns nothing; a new path produces the expected value.
     → **Fix**: prepend the new path to `paths`, KEEP the old path as last-resort fallback.
   - **Case B — Enum value changed** (in `itemFilter.equals` or `transform` comparisons): the live data has a new enum.
     → **Fix**: add the new value to `itemFilter.equals`, keep old values.
   - **Case C — Nested structure changed**: e.g. `{a: {b: X}}` became `{a: [{b: X}]}`.
     → **Fix**: use `a[0].b` or `a[*].b` (whichever matches) as a NEW path prepended; keep the old as fallback.
   - **Case D — The field was removed entirely**: the upstream dropped this concept.
     → **Fix**: remove the field from the route IF no consumer depends on it (grep `MetadataFetcher.swift` for `row["<fieldName>"]`). If consumers depend on it, **stop and open a human issue** — a Swift code change is needed.
   - **Case E — Response shape changed root-level**: `itemsPath` no longer resolves.
     → **Fix**: update `itemsPath`; keep old itemsPath in the adapter's `description` with date stamp for lineage.
   - **Case F — Expected value was stale**: the upstream has a new correct value (e.g. cited_by_count changed from 40k to 80k over 5 years).
     → **Fix**: update `canary[].expectSearch.<fieldName>` to the new truth. DO NOT use this for cases A–E.

### Step 2.4 — Apply the minimal patch

Emit a JSON patch that:
1. Changes `schemaVersion` by +1
2. Updates ONLY the affected fields / itemsPath / filter
3. Preserves all other paths and strategies

### Step 2.5 — Validate schema compliance

The patched JSON must conform to `Docs/adapter-schema.json`. Key checks:
- Every `transform` value is in the enum list
- Every `postProcess` value is in the enum list
- Every `kind` value is `"http"` (you cannot use `webView` until executor lands)
- Every `extract.kind` is `"json"` or `"html"` (never `"xml"`)

If you cannot fix within these constraints, **stop and emit a human issue** with:
- Which capability is missing
- Suggested Swift-side change (to `SiteAdapterRuntime.swift`)
- Minimal reproducer

### Step 2.6 — Re-verify empirically

```bash
# Build + static test
swift test --filter SwiftLibCoreTests

# Live canary
SWIFTLIB_CANARY=1 swift test --filter CanaryIntegrationTests
```

Both must pass before the patch is considered valid. If the live canary is flaky (network/rate-limit), wait 30s and retry up to 3 times.

### Step 2.7 — Emit the change

Open a PR titled: `adapter: fix <$ADAPTER_ID> <one-line drift summary>`

PR body MUST include:
- The failing `$ASSERTION`
- Link to the live response capture
- Diagnosis (Case A–F from Step 2.3)
- Proof: both test outputs from Step 2.6
- Diff summary (added paths, kept paths)

**DO NOT auto-merge.** Human review required.

---

## 3. Failure modes you must NOT attempt to fix here

If the diagnosis falls into any of these, **do not patch the adapter — open a human-labeled issue instead**:

| Symptom | Reason |
|---|---|
| The upstream now requires auth (API key / OAuth / session cookie) | Needs Swift-side credential handling + possibly `kind: webView` executor |
| The upstream returns XML / RSS / CSV | Adapter runtime doesn't support these formats yet |
| The upstream needs POST with a body | Runtime only supports GET |
| The expected field needs cross-record aggregation (e.g. "count of citations in 2024") | Runtime is stateless per-row |
| All paths resolve but the STRINGIFIED value disagrees with expected by a meaningful transform (e.g. expected "101–120" but got "101-120" en-dash vs hyphen) | Needs a new transform — tell humans |
| Canary for EVERY adapter fails simultaneously | Likely a network / CI / sandbox issue, not drift |

---

## 4. Prompt template (copy-paste-ready)

If you are being driven by an LLM-as-agent, the enclosing system prompt should look like:

```
You are an adapter repair agent for SwiftLib. Read:
  1. Docs/ADAPTERS_REPAIR.md (this file; the definitive playbook)
  2. Docs/adapter-schema.json (valid syntax)
  3. Sources/SwiftLibCore/Resources/adapters/{{adapter_id}}.json (the drifted file)

Failure context:
  adapter     = {{adapter_id}}
  canary_name = {{canary_name}}
  route       = {{route_name}}
  context     = {{context_json}}
  expected    = {{expected_json}}
  assertion   = {{assertion_text}}

Hard constraints:
  - You may only output one tool call: `apply_adapter_patch(id, patch_json)`.
  - The patch MUST validate against Docs/adapter-schema.json.
  - You MUST keep old paths as fallbacks.
  - You MUST bump schemaVersion.
  - You MUST have run `curl` against the live URL and attached the relevant excerpt as evidence.
  - If the diagnosis is not Case A–F (see § 2.3), do NOT emit a patch — respond with `open_issue(...)`.

After patching, run:
  SWIFTLIB_CANARY=1 swift test --filter CanaryIntegrationTests

Only proceed to open a PR if BOTH static tests and the live canary pass.
```

---

## 5. Worked example (real drift we fixed)

**Drift**: OpenAlex removed `grants` from `select=`, split into `awards` + `funders`.

**Assertion**: `openalex-work.byDoi returned 0 rows` (actually got `{error: "grants is not a valid select field"}`)

**Diagnosis**: Case A (renamed) + Case E (select= URL parameter invalid).

**Patch applied**:
```diff
-  "schemaVersion": 1,
+  "schemaVersion": 2,
   "routes": {
     "byDoi": {
-      "url": "...&select=...,grants&mailto={mailto}",
+      "url": "...&select=...,awards,funders&mailto={mailto}",
       "extract": {
         "fields": {
-          "grantFunders": { "paths": ["grants[*].funder_display_name"], "separator": "|" },
-          "grantAwards":  { "paths": ["grants[*].award_id"],             "separator": "|" }
+          "grantFunders": { "paths": ["awards[*].funder_display_name", "funders[*].display_name"], "separator": "|" },
+          "grantAwards":  { "paths": ["awards[*].funder_award_id"],                                "separator": "|" }
         }
       }
     }
   }
```

Old paths dropped (Case D — they're invalid select keys). New paths added. New fallback `funders[*].display_name` covers the case where only `funders` is populated.

Canary confirmed fixed. PR opened for human review. `schemaVersion` bumped 1→2.
