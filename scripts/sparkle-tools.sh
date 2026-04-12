#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SPARKLE_PROJECT_DIR="${SPARKLE_PROJECT_DIR:-$PROJECT_DIR/.build/checkouts/Sparkle}"
SPARKLE_DERIVED_DATA="${SPARKLE_DERIVED_DATA:-$PROJECT_DIR/.xcodebuild-sparkle-tools}"
SPARKLE_CONFIGURATION="${SPARKLE_CONFIGURATION:-Release}"

usage() {
    cat <<'EOF'
Usage:
  scripts/sparkle-tools.sh tool-path <generate_keys|generate_appcast>
  scripts/sparkle-tools.sh public-key [account]
  scripts/sparkle-tools.sh generate-keys [account]
  scripts/sparkle-tools.sh generate-appcast [args...]
EOF
}

ensure_sparkle_source() {
    if [ ! -d "$SPARKLE_PROJECT_DIR" ] || [ ! -f "$SPARKLE_PROJECT_DIR/Sparkle.xcodeproj/project.pbxproj" ]; then
        echo "error: Sparkle source checkout was not found at $SPARKLE_PROJECT_DIR" >&2
        exit 1
    fi
}

build_tool() {
    local scheme="$1"

    ensure_sparkle_source

    xcodebuild \
        -project "$SPARKLE_PROJECT_DIR/Sparkle.xcodeproj" \
        -scheme "$scheme" \
        -configuration "$SPARKLE_CONFIGURATION" \
        -derivedDataPath "$SPARKLE_DERIVED_DATA" \
        build \
        -quiet >&2

    printf '%s\n' "$SPARKLE_DERIVED_DATA/Build/Products/$SPARKLE_CONFIGURATION/$scheme"
}

main() {
    if [ "$#" -lt 1 ]; then
        usage
        exit 1
    fi

    local command="$1"
    shift

    case "$command" in
        tool-path)
            if [ "$#" -ne 1 ]; then
                usage
                exit 1
            fi
            build_tool "$1"
            ;;
        public-key)
            local account="${1:-com.swiftlib.app}"
            local tool
            tool="$(build_tool generate_keys)"
            "$tool" -p --account "$account"
            ;;
        generate-keys)
            local account="${1:-com.swiftlib.app}"
            local tool
            tool="$(build_tool generate_keys)"
            exec "$tool" --account "$account"
            ;;
        generate-appcast)
            local tool
            tool="$(build_tool generate_appcast)"
            exec "$tool" "$@"
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

main "$@"
