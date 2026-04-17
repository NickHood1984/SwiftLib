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
OUTPUT_DIR="$PROJECT_DIR/build"
STAGING_DIR="$OUTPUT_DIR/dmg-staging"

APP_NAME="SwiftLib"
CLI_NAME="swiftlib-cli"
APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"
APP_VERSION="${APP_VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}"
APP_VERSION="${APP_VERSION:-1.2.1}"
APP_BUILD_VERSION="${APP_BUILD_VERSION:-$APP_VERSION}"
if [ "$CONFIGURATION" = "Release" ]; then
    DMG_NAME="$APP_NAME-$APP_VERSION.dmg"
else
    DMG_NAME="$APP_NAME-$APP_VERSION-${CONFIGURATION}.dmg"
fi
DMG_PATH="$OUTPUT_DIR/$DMG_NAME"
FRAMEWORKS_DIR="$APP_BUNDLE/Contents/Frameworks"

if [ -f "$PROJECT_DIR/Package.swift" ] && [ ! -d "$PROJECT_DIR/$APP_NAME.xcodeproj" ] && [ ! -d "$PROJECT_DIR/$APP_NAME.xcworkspace" ]; then
    BUILD_SYSTEM="swiftpm"
    if [ "$CONFIGURATION" = "Release" ]; then
        SWIFTPM_CONFIGURATION="release"
    else
        SWIFTPM_CONFIGURATION="debug"
    fi
    PRODUCTS_DIR="$PROJECT_DIR/.build/arm64-apple-macosx/$SWIFTPM_CONFIGURATION"
else
    BUILD_SYSTEM="xcodebuild"
    PRODUCTS_DIR="$DERIVED_DATA/Build/Products/$CONFIGURATION"
fi

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
SPARKLE_KEYS_ACCOUNT="${SPARKLE_KEYS_ACCOUNT:-com.swiftlib.app}"

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

# Sparkle auto-update configuration
# Set these environment variables before building, or override the defaults below.
# Feed URL defaults to GitHub Pages for the current origin repository.
DEFAULT_GITHUB_REPO="$(infer_github_repo_path || true)"
if [ -n "$DEFAULT_GITHUB_REPO" ]; then
    DEFAULT_GITHUB_OWNER="${DEFAULT_GITHUB_REPO%%/*}"
    DEFAULT_GITHUB_REPO_NAME="${DEFAULT_GITHUB_REPO#*/}"
    DEFAULT_SPARKLE_FEED_URL="https://${DEFAULT_GITHUB_OWNER}.github.io/${DEFAULT_GITHUB_REPO_NAME}/Docs/appcast.xml"
else
    DEFAULT_SPARKLE_FEED_URL="https://example.com/appcast.xml"
fi
SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-$DEFAULT_SPARKLE_FEED_URL}"

resolve_sparkle_public_key() {
    if [ -n "${SPARKLE_ED_PUBLIC_KEY:-}" ] && [ "${SPARKLE_ED_PUBLIC_KEY}" != "REPLACE_WITH_YOUR_PUBLIC_KEY" ]; then
        printf '%s\n' "${SPARKLE_ED_PUBLIC_KEY}"
        return 0
    fi

    if [ -x "$SCRIPT_DIR/sparkle-tools.sh" ]; then
        local looked_up_key
        if looked_up_key="$("$SCRIPT_DIR/sparkle-tools.sh" public-key "$SPARKLE_KEYS_ACCOUNT" 2>/dev/null)"; then
            looked_up_key="$(printf '%s' "$looked_up_key" | tr -d '\n')"
            if [ -n "$looked_up_key" ]; then
                printf '%s\n' "$looked_up_key"
                return 0
            fi
        fi
    fi

    printf '%s\n' "REPLACE_WITH_YOUR_PUBLIC_KEY"
}

SPARKLE_ED_PUBLIC_KEY="$(resolve_sparkle_public_key)"
if [ "$SPARKLE_ED_PUBLIC_KEY" = "REPLACE_WITH_YOUR_PUBLIC_KEY" ]; then
    echo "warning: Sparkle public key is not configured; updates will not validate until a key is generated." >&2
fi

json_field() {
    local json="$1"
    local expr="$2"
    node -e "const data = JSON.parse(process.argv[1]); const value = ${expr}; if (value == null) process.stdout.write(''); else process.stdout.write(String(value));" "$json"
}

build_app() {
    echo "▸ Building $APP_NAME app ($CONFIGURATION)..."
    if [ "$BUILD_SYSTEM" = "swiftpm" ]; then
        if [ "$CONFIGURATION" = "Release" ]; then
            swift build -c release --product "$APP_NAME"
        else
            swift build --product "$APP_NAME"
        fi
    else
        # Reusing DerivedData with SwiftPM package graphs can leave behind
        # stale bare repositories that make xcodebuild fail with
        # "already exists in file system" during dependency resolution.
        rm -rf "$DERIVED_DATA/SourcePackages"
        xcodebuild build \
            -scheme "$APP_NAME" \
            -configuration "$CONFIGURATION" \
            -destination 'platform=macOS' \
            -derivedDataPath "$DERIVED_DATA" \
            -quiet
    fi
}

build_cli() {
    echo "▸ Building $CLI_NAME CLI ($CONFIGURATION)..."
    if [ "$BUILD_SYSTEM" = "swiftpm" ]; then
        if [ "$CONFIGURATION" = "Release" ]; then
            swift build -c release --product "$CLI_NAME"
        else
            swift build --product "$CLI_NAME"
        fi
    else
        xcodebuild build \
            -scheme "$CLI_NAME" \
            -configuration "$CONFIGURATION" \
            -destination 'platform=macOS' \
            -derivedDataPath "$DERIVED_DATA" \
            -quiet
    fi
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
    mkdir -p "$FRAMEWORKS_DIR"
    cp "$PRODUCTS_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

    for bundle in "$PRODUCTS_DIR"/*.bundle; do
        [ -d "$bundle" ] && cp -R "$bundle" "$APP_BUNDLE/Contents/Resources/"
    done

    cat > "$APP_BUNDLE/Contents/Info.plist" << PLIST
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
    <string>${APP_BUILD_VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
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
    <key>SUFeedURL</key>
    <string>${SPARKLE_FEED_URL}</string>
    <key>SUPublicEDKey</key>
    <string>${SPARKLE_ED_PUBLIC_KEY}</string>
    <key>SUEnableInstallerLauncherService</key>
    <true/>
</dict>
</plist>
PLIST
}

add_binary_rpath_if_missing() {
    local binary="$1"
    local rpath="$2"
    if ! otool -l "$binary" | awk '/LC_RPATH/{getline; getline; print $2}' | grep -Fx "$rpath" >/dev/null 2>&1; then
        install_name_tool -add_rpath "$rpath" "$binary"
    fi
}

remove_development_rpaths() {
    local binary="$1"
    local existing_rpaths
    existing_rpaths="$(otool -l "$binary" | awk '/LC_RPATH/{getline; getline; print $2}' || true)"
    while IFS= read -r rpath; do
        [ -z "$rpath" ] && continue
        if printf '%s' "$rpath" | grep -q 'PackageFrameworks'; then
            install_name_tool -delete_rpath "$rpath" "$binary"
        fi
    done <<EOF
$existing_rpaths
EOF
}

embed_sparkle_runtime() {
    local sparkle_framework_src="$PRODUCTS_DIR/Sparkle.framework"
    local main_binary="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

    if [ ! -d "$sparkle_framework_src" ]; then
        echo "error: Sparkle.framework was not produced by the build." >&2
        exit 1
    fi

    echo "▸ Embedding Sparkle runtime..."
    rm -rf "$FRAMEWORKS_DIR/Sparkle.framework"
    cp -R "$sparkle_framework_src" "$FRAMEWORKS_DIR/"

    add_binary_rpath_if_missing "$main_binary" "@executable_path/../Frameworks"
    remove_development_rpaths "$main_binary"
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

    if [ -d "$FRAMEWORKS_DIR" ]; then
        while IFS= read -r nested_binary; do
            codesign_target "$nested_binary"
        done < <(find "$FRAMEWORKS_DIR" -type f \( -name 'Autoupdate' -o -perm -111 \) ! -path '*/_CodeSignature/*' | sort)

        while IFS= read -r nested_bundle; do
            codesign_target "$nested_bundle"
        done < <(find "$FRAMEWORKS_DIR" -depth \( -name '*.xpc' -o -name '*.app' -o -name '*.framework' \) | sort)
    fi

    codesign --force --deep --sign "$CODESIGN_IDENTITY" --timestamp=none "$APP_BUNDLE"
}

embed_app_icon() {
    local icon_src="$PROJECT_DIR/图标.png"
    if [ ! -f "$icon_src" ]; then
        echo "▸ 跳过图标嵌入（未找到 图标.png）"
        return
    fi
    echo "▸ Embedding app icon..."
    local iconset
    iconset="$(mktemp -d).iconset"
    mkdir -p "$iconset"
    sips -z 16   16   "$icon_src" --out "$iconset/icon_16x16.png"    >/dev/null
    sips -z 32   32   "$icon_src" --out "$iconset/icon_16x16@2x.png" >/dev/null
    sips -z 32   32   "$icon_src" --out "$iconset/icon_32x32.png"    >/dev/null
    sips -z 64   64   "$icon_src" --out "$iconset/icon_32x32@2x.png" >/dev/null
    sips -z 128  128  "$icon_src" --out "$iconset/icon_128x128.png"       >/dev/null
    sips -z 256  256  "$icon_src" --out "$iconset/icon_128x128@2x.png"    >/dev/null
    sips -z 256  256  "$icon_src" --out "$iconset/icon_256x256.png"       >/dev/null
    sips -z 512  512  "$icon_src" --out "$iconset/icon_256x256@2x.png"    >/dev/null
    sips -z 512  512  "$icon_src" --out "$iconset/icon_512x512.png"       >/dev/null
    sips -z 1024 1024 "$icon_src" --out "$iconset/icon_512x512@2x.png"    >/dev/null
    iconutil -c icns "$iconset" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    rm -rf "$iconset"
    # 确保 Info.plist 中有 CFBundleIconFile
    if ! /usr/libexec/PlistBuddy -c "Print :CFBundleIconFile" "$APP_BUNDLE/Contents/Info.plist" >/dev/null 2>&1; then
        /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP_BUNDLE/Contents/Info.plist"
    else
        /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$APP_BUNDLE/Contents/Info.plist"
    fi
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
embed_sparkle_runtime
embed_app_icon
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
