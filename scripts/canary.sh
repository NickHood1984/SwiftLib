#!/usr/bin/env bash
# Run the adapter canary suite against live upstream URLs.
#
# These tests are opt-in (they hit the real network) and gated by
# SWIFTLIB_CANARY=1 so they don't run during normal `swift test`.
#
# Usage:
#   ./scripts/canary.sh                 # run all canaries
#   ./scripts/canary.sh douban-book     # only the douban-book adapter's cases
#
# Exit code:
#   0 — every canary passed
#   non-zero — at least one drifted; see log for which field/source changed

set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

FILTER="CanaryIntegrationTests"
if [[ $# -gt 0 ]]; then
  # Narrowing to a specific adapter isn't supported because the harness
  # iterates every adapter automatically. If you need a per-adapter run,
  # temporarily remove the others from Resources/adapters or pass a filter
  # that matches only `testAllBundledAdaptersCanary`.
  echo "note: per-adapter filtering not supported; running full canary suite." >&2
fi

echo "→ SWIFTLIB_CANARY=1 swift test --filter $FILTER"
SWIFTLIB_CANARY=1 swift test --filter "$FILTER"
status=$?

if [[ $status -ne 0 ]]; then
  cat >&2 <<'EOF'

✗ Canary failed. A source's schema has likely drifted.

Next steps:
  1. Identify the failing field from the XCTAssert output.
  2. curl the failing URL manually and diff the live response against
     Resources/adapters/<id>.json.
  3. Edit the JSON: add new paths/strategies, KEEP the old ones as fallback.
  4. Bump schemaVersion and rerun this script.

Full playbook: Docs/ADAPTERS.md § 3
EOF
fi

exit $status
