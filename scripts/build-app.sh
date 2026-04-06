#!/bin/bash
set -euo pipefail

MODE="${1:-debug}"
if [ "$MODE" = "release" ]; then
    CONFIGURATION="Release"
else
    CONFIGURATION="Debug"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

DERIVED_DATA="$PROJECT_DIR/.xcodebuild"
PRODUCTS_DIR="$DERIVED_DATA/Build/Products/$CONFIGURATION"
OUTPUT_DIR="$PROJECT_DIR/build"
STAGING_DIR="$OUTPUT_DIR/dmg-staging"

APP_NAME="SwiftLib"
CLI_NAME="swiftlib-cli"
APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"
DMG_NAME="$APP_NAME-${CONFIGURATION}.dmg"
DMG_PATH="$OUTPUT_DIR/$DMG_NAME"

BACKEND_DIR="$PROJECT_DIR/swiftlib-translation-backend"
BACKEND_RESOURCE_DIR="$APP_BUNDLE/Contents/Resources/TranslationBackend"
BACKEND_SEED_DIR="$APP_BUNDLE/Contents/Resources/TranslationBackendSeed"
BACKEND_MANIFEST_PATH="$APP_BUNDLE/Contents/Resources/TranslationBackendManifest.json"
HELPERS_DIR="$APP_BUNDLE/Contents/Helpers"

NODE_VERSION="${NODE_VERSION:-$(node --version 2>/dev/null | sed 's/^v//' || true)}"
NODE_VERSION="${NODE_VERSION:-25.8.1}"
NODE_ARCH="${NODE_ARCH:-darwin-arm64}"
NODE_DIST_BASENAME="node-v${NODE_VERSION}-${NODE_ARCH}"
NODE_CACHE_DIR="$PROJECT_DIR/.cache/node/${NODE_DIST_BASENAME}"
NODE_TARBALL="$NODE_CACHE_DIR/${NODE_DIST_BASENAME}.tar.gz"
NODE_DIST_URL="${NODE_DIST_URL:-https://nodejs.org/dist/v${NODE_VERSION}/${NODE_DIST_BASENAME}.tar.gz}"
NODE_DIST_DIR="$NODE_CACHE_DIR/${NODE_DIST_BASENAME}"

CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
CODESIGN_ENABLED="${CODESIGN_ENABLED:-1}"

json_field() {
    local json="$1"
    local expr="$2"
    node -e "const data = JSON.parse(process.argv[1]); const value = ${expr}; if (value == null) process.stdout.write(''); else process.stdout.write(String(value));" "$json"
}

build_app() {
    echo "▸ Building $APP_NAME app ($CONFIGURATION)..."
    xcodebuild build \
        -scheme "$APP_NAME" \
        -configuration "$CONFIGURATION" \
        -destination 'platform=macOS' \
        -derivedDataPath "$DERIVED_DATA" \
        -quiet
}

build_cli() {
    echo "▸ Building $CLI_NAME CLI ($CONFIGURATION)..."
    xcodebuild build \
        -scheme "$CLI_NAME" \
        -configuration "$CONFIGURATION" \
        -destination 'platform=macOS' \
        -derivedDataPath "$DERIVED_DATA" \
        -quiet
}

assemble_app_bundle() {
    echo "▸ Assembling $APP_NAME.app..."
    rm -rf "$APP_BUNDLE"
    mkdir -p "$OUTPUT_DIR"

    if [ -d "$PRODUCTS_DIR/$APP_NAME.app" ]; then
        cp -R "$PRODUCTS_DIR/$APP_NAME.app" "$APP_BUNDLE"
        return
    fi

    mkdir -p "$APP_BUNDLE/Contents/MacOS"
    mkdir -p "$APP_BUNDLE/Contents/Resources"
    cp "$PRODUCTS_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

    for bundle in "$PRODUCTS_DIR"/*.bundle; do
        [ -d "$bundle" ] && cp -R "$bundle" "$APP_BUNDLE/Contents/Resources/"
    done

    cat > "$APP_BUNDLE/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>SwiftLib</string>
    <key>CFBundleIdentifier</key>
    <string>com.swiftlib.app</string>
    <key>CFBundleName</key>
    <string>SwiftLib</string>
    <key>CFBundleDisplayName</key>
    <string>SwiftLib</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsLocalNetworking</key>
        <true/>
    </dict>
</dict>
</plist>
PLIST
}

prepare_backend_overlay() {
    echo "▸ Building translators overlay..."
    (cd "$BACKEND_DIR" && node scripts/build-overlay.mjs >/dev/null)
}

download_node_runtime() {
    echo "▸ Preparing bundled Node.js runtime ($NODE_VERSION)..."
    mkdir -p "$NODE_CACHE_DIR"
    if [ ! -x "$NODE_DIST_DIR/bin/node" ]; then
        if [ ! -f "$NODE_TARBALL" ]; then
            curl -fsSL "$NODE_DIST_URL" -o "$NODE_TARBALL"
        fi
        rm -rf "$NODE_DIST_DIR"
        tar -xzf "$NODE_TARBALL" -C "$NODE_CACHE_DIR"
    fi
}

embed_helpers() {
    echo "▸ Embedding CLI and Node runtimes..."
    mkdir -p "$HELPERS_DIR"
    cp "$PRODUCTS_DIR/$CLI_NAME" "$HELPERS_DIR/$CLI_NAME"
    chmod 755 "$HELPERS_DIR/$CLI_NAME"
    cp "$NODE_DIST_DIR/bin/node" "$HELPERS_DIR/node"
    chmod 755 "$HELPERS_DIR/node"
}

embed_backend_runtime() {
    echo "▸ Embedding translation backend runtime..."
    rm -rf "$BACKEND_RESOURCE_DIR" "$BACKEND_SEED_DIR"
    mkdir -p "$BACKEND_RESOURCE_DIR" "$BACKEND_SEED_DIR/runtime" "$BACKEND_RESOURCE_DIR/licenses"

    local revisions_json
    revisions_json="$(cd "$BACKEND_DIR" && node scripts/update-translators.mjs)"
    local translation_server_revision
    local translators_cn_revision
    translation_server_revision="$(json_field "$revisions_json" 'data.translationServerRevision')"
    translators_cn_revision="$(json_field "$revisions_json" 'data.translatorsCNRevision')"
    local overlay_revision="${translation_server_revision}+${translators_cn_revision}"
    local backend_version
    backend_version="$(node -e "const fs=require('fs'); const p=JSON.parse(fs.readFileSync(process.argv[1],'utf8')); process.stdout.write(p.version);" "$BACKEND_DIR/package.json")"
    local licenses_version="${LICENSES_VERSION:-${backend_version}-${NODE_VERSION}}"

    cp "$BACKEND_DIR/server.js" "$BACKEND_RESOURCE_DIR/server.js"
    cp "$BACKEND_DIR/package.json" "$BACKEND_RESOURCE_DIR/package.json"
    mkdir -p "$BACKEND_RESOURCE_DIR/config"
    cp "$BACKEND_DIR/config/upstream-revisions.json" "$BACKEND_RESOURCE_DIR/config/upstream-revisions.json"

    mkdir -p "$BACKEND_RESOURCE_DIR/vendor/translation-server"
    rsync -a --delete \
        --exclude '.git' \
        "$BACKEND_DIR/vendor/translation-server/config" \
        "$BACKEND_DIR/vendor/translation-server/src" \
        "$BACKEND_DIR/vendor/translation-server/modules" \
        "$BACKEND_DIR/vendor/translation-server/node_modules" \
        "$BACKEND_DIR/vendor/translation-server/package.json" \
        "$BACKEND_DIR/vendor/translation-server/package-lock.json" \
        "$BACKEND_RESOURCE_DIR/vendor/translation-server/"

    rsync -a --delete "$BACKEND_DIR/runtime/" "$BACKEND_SEED_DIR/runtime/"

    cp "$BACKEND_DIR/vendor/translation-server/COPYING" "$BACKEND_RESOURCE_DIR/licenses/translation-server-LICENSE.txt"
    cp "$BACKEND_DIR/vendor/translators_CN/LICENSE" "$BACKEND_RESOURCE_DIR/licenses/translators_CN-LICENSE.txt"
    cp "$NODE_DIST_DIR/LICENSE" "$BACKEND_RESOURCE_DIR/licenses/node-LICENSE.txt"

    cat > "$BACKEND_RESOURCE_DIR/OPEN_SOURCE_NOTICES.txt" <<EOF
SwiftLib 中文元数据后端包含以下第三方组件：

1. translation-server
   Revision: ${translation_server_revision}
   License file: licenses/translation-server-LICENSE.txt

2. translators_CN
   Revision: ${translators_cn_revision}
   License file: licenses/translators_CN-LICENSE.txt

3. Node.js runtime
   Version: ${NODE_VERSION}
   License file: licenses/node-LICENSE.txt
EOF

    cat > "$BACKEND_MANIFEST_PATH" <<EOF
{
  "backendVersion": "${backend_version}",
  "nodeVersion": "${NODE_VERSION}",
  "nodePath": "Contents/Helpers/node",
  "backendRootPath": "Contents/Resources/TranslationBackend",
  "backendEntryPath": "Contents/Resources/TranslationBackend/server.js",
  "seedRootPath": "Contents/Resources/TranslationBackendSeed",
  "translationServerRevision": "${translation_server_revision}",
  "translatorsCNRevision": "${translators_cn_revision}",
  "overlayRevision": "${overlay_revision}",
  "licensesVersion": "${licenses_version}"
}
EOF
}

codesign_target() {
    local target="$1"
    if [ "$CODESIGN_ENABLED" != "0" ]; then
        codesign --force --sign "$CODESIGN_IDENTITY" --timestamp=none "$target"
    fi
}

sign_bundle() {
    if [ "$CODESIGN_ENABLED" = "0" ]; then
        return
    fi

    echo "▸ Codesigning embedded helpers and app bundle..."
    codesign_target "$HELPERS_DIR/node"
    codesign_target "$HELPERS_DIR/$CLI_NAME"

    while IFS= read -r dylib; do
        codesign_target "$dylib"
    done < <(find "$BACKEND_RESOURCE_DIR/vendor/translation-server/node_modules" -type f \( -name '*.node' -o -name '*.dylib' \) 2>/dev/null | sort)

    codesign --force --deep --sign "$CODESIGN_IDENTITY" --timestamp=none "$APP_BUNDLE"
}

create_dmg() {
    echo "▸ Creating DMG..."
    rm -rf "$STAGING_DIR" "$DMG_PATH"
    mkdir -p "$STAGING_DIR"
    cp -R "$APP_BUNDLE" "$STAGING_DIR/"
    hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH" >/dev/null
}

build_app
build_cli
assemble_app_bundle
prepare_backend_overlay
download_node_runtime
embed_helpers
embed_backend_runtime
sign_bundle
create_dmg

APP_SIZE=$(du -sh "$APP_BUNDLE" | cut -f1 | xargs)
DMG_SIZE=$(du -sh "$DMG_PATH" | cut -f1 | xargs)

echo ""
echo "✅ Done!  App=${APP_SIZE}  DMG=${DMG_SIZE}"
echo "   App: $APP_BUNDLE"
echo "   DMG: $DMG_PATH"
echo ""
echo "   运行 App: open \"$APP_BUNDLE\""
echo "   发行包:   \"$DMG_PATH\""
