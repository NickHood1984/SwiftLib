#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

APP_NAME="${APP_NAME:-SwiftLib}"
APP_VERSION="${APP_VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}"
APP_VERSION="${APP_VERSION:-1.1.1}"
APP_BUILD_VERSION="${APP_BUILD_VERSION:-$APP_VERSION}"
SPARKLE_KEYS_ACCOUNT="${SPARKLE_KEYS_ACCOUNT:-com.swiftlib.app}"
RELEASE_TAG="${RELEASE_TAG:-v$APP_VERSION}"

infer_github_repo_path() {
    local remote_url
    remote_url="$(git remote get-url origin 2>/dev/null || true)"

    case "$remote_url" in
        git@github.com:*)
            remote_url="${remote_url#git@github.com:}"
            ;;
        ssh://git@github.com/*)
            remote_url="${remote_url#ssh://git@github.com/}"
            ;;
        https://github.com/*)
            remote_url="${remote_url#https://github.com/}"
            ;;
        *)
            return 1
            ;;
    esac

    remote_url="${remote_url%.git}"
    printf '%s\n' "$remote_url"
}

GITHUB_REPO_PATH="${GITHUB_REPO_PATH:-$(infer_github_repo_path || true)}"
if [ -z "$GITHUB_REPO_PATH" ]; then
    echo "error: unable to infer GitHub repository from origin remote; set GITHUB_REPO_PATH=owner/repo." >&2
    exit 1
fi

GITHUB_OWNER="${GITHUB_REPO_PATH%%/*}"
GITHUB_REPO="${GITHUB_REPO_PATH#*/}"
REPO_URL="https://github.com/$GITHUB_OWNER/$GITHUB_REPO"
PAGES_BASE_URL="${PAGES_BASE_URL:-https://${GITHUB_OWNER}.github.io/${GITHUB_REPO}}"
DOWNLOAD_URL_PREFIX="${DOWNLOAD_URL_PREFIX:-${REPO_URL}/releases/download/${RELEASE_TAG}/}"
FULL_RELEASE_NOTES_URL="${FULL_RELEASE_NOTES_URL:-${REPO_URL}/releases/tag/${RELEASE_TAG}}"
RELEASE_NOTES_URL_PREFIX="${RELEASE_NOTES_URL_PREFIX:-${PAGES_BASE_URL}/releases/}"

ARCHIVES_DIR="${ARCHIVES_DIR:-$PROJECT_DIR/build/sparkle-archives}"
APPCAST_PATH="${APPCAST_PATH:-$PROJECT_DIR/Docs/appcast.xml}"
PAGES_RELEASE_NOTES_DIR="${PAGES_RELEASE_NOTES_DIR:-$PROJECT_DIR/Docs/releases}"
DMG_PATH="${DMG_PATH:-$PROJECT_DIR/build/$APP_NAME-$APP_VERSION.dmg}"
NOTES_SOURCE_FILE="${NOTES_SOURCE_FILE:-}"

normalize_historical_release_urls() {
    local archive_path archive_name archive_version expected_url current_url

    for archive_path in "$ARCHIVES_DIR"/"$APP_NAME"-*.dmg; do
        [ -e "$archive_path" ] || continue

        archive_name="$(basename "$archive_path")"
        archive_version="${archive_name#${APP_NAME}-}"
        archive_version="${archive_version%.dmg}"
        expected_url="${REPO_URL}/releases/download/v${archive_version}/${archive_name}"
        current_url="${DOWNLOAD_URL_PREFIX}${archive_name}"

        APPCAST_EXPECTED_URL="$expected_url" \
            perl -0pi -e 's|\Q'$current_url'\E|$ENV{APPCAST_EXPECTED_URL}|g' "$APPCAST_PATH"
    done
}

if [ ! -f "$DMG_PATH" ]; then
    APP_VERSION="$APP_VERSION" APP_BUILD_VERSION="$APP_BUILD_VERSION" "$SCRIPT_DIR/build-app.sh" release
fi

if [ ! -f "$DMG_PATH" ]; then
    echo "error: release DMG not found at $DMG_PATH" >&2
    exit 1
fi

mkdir -p "$ARCHIVES_DIR"
mkdir -p "$(dirname "$APPCAST_PATH")"
mkdir -p "$PAGES_RELEASE_NOTES_DIR"
: > "$PROJECT_DIR/Docs/.nojekyll"

ARCHIVE_BASENAME="$(basename "$DMG_PATH")"
cp -f "$DMG_PATH" "$ARCHIVES_DIR/$ARCHIVE_BASENAME"

if [ -n "$NOTES_SOURCE_FILE" ]; then
    NOTES_EXT="${NOTES_SOURCE_FILE##*.}"
    cp -f "$NOTES_SOURCE_FILE" "$ARCHIVES_DIR/${ARCHIVE_BASENAME%.*}.$NOTES_EXT"
    cp -f "$NOTES_SOURCE_FILE" "$PAGES_RELEASE_NOTES_DIR/${ARCHIVE_BASENAME%.*}.$NOTES_EXT"
fi

key_args=(--account "$SPARKLE_KEYS_ACCOUNT")
if [ -n "${SPARKLE_PRIVATE_ED_KEY_FILE:-}" ]; then
    key_args=(--ed-key-file "$SPARKLE_PRIVATE_ED_KEY_FILE")
fi

"$SCRIPT_DIR/sparkle-tools.sh" generate-appcast \
    "${key_args[@]}" \
    --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
    --release-notes-url-prefix "$RELEASE_NOTES_URL_PREFIX" \
    --full-release-notes-url "$FULL_RELEASE_NOTES_URL" \
    --link "$REPO_URL" \
    -o "$APPCAST_PATH" \
    "$ARCHIVES_DIR"

normalize_historical_release_urls

echo ""
echo "Appcast generated:"
echo "  $APPCAST_PATH"
echo "Local archive staged at:"
echo "  $ARCHIVES_DIR/$ARCHIVE_BASENAME"
echo ""
echo "Upload the DMG to GitHub Release $RELEASE_TAG and publish docs/ via GitHub Pages."
