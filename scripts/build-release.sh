#!/bin/bash
# build-release.sh — clean release build + optional GitHub publish for Browser Picker
#
# Usage:
#   ./scripts/build-release.sh                         # build only
#   ./scripts/build-release.sh --version 1.0.1           # explicit version
#   ./scripts/build-release.sh --publish               # build + publish to GitHub Releases
#   ./scripts/build-release.sh --version 1.0.1 --publish
#   ./scripts/build-release.sh --publish --draft        # publish as draft
#
# Requires: xcodegen, gh (GitHub CLI) — install with: brew install gh xcodegen
# Output:   dist/BrowserPicker-<version>.zip

set -euo pipefail

BOLD="\033[1m"
GREEN="\033[32m"
BLUE="\033[34m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"

step() { echo -e "\n${BLUE}${BOLD}▶ $1${RESET}"; }
ok()   { echo -e "${GREEN}${BOLD}✓ $1${RESET}"; }
warn() { echo -e "${YELLOW}⚠ $1${RESET}"; }
fail() { echo -e "${RED}${BOLD}✗ $1${RESET}"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="BrowserPicker"
PROJECT="$PROJECT_ROOT/${APP_NAME}.xcodeproj"
SCHEME="$APP_NAME"
DIST_DIR="$PROJECT_ROOT/dist"
BUILD_DIR="$PROJECT_ROOT/build"
SPARKLE_VERSION="2.6.4"
SPARKLE_TOOLS_DIR="$SCRIPT_DIR/sparkle-tools"
SIGN_UPDATE="$SPARKLE_TOOLS_DIR/bin/sign_update"
APPCAST_PATH="$PROJECT_ROOT/docs/appcast.xml"

VERSION=""
PUBLISH=false
DRAFT=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        --publish) PUBLISH=true; shift ;;
        --draft)   DRAFT=true;   shift ;;
        *) fail "Unknown argument: $1" ;;
    esac
done

if [[ -z "$VERSION" ]]; then
    VERSION=$(defaults read "$PROJECT_ROOT/BrowserPicker/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "1.0")
fi

ZIP_NAME="${APP_NAME}-${VERSION}.zip"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"

echo -e "\n${BOLD}Building ${APP_NAME} v${VERSION}${RESET}"
echo "────────────────────────────────────────"

# ── Sparkle tools ────────────────────────────────────────────────────────────

step "Checking Sparkle tools"
if [[ ! -x "$SIGN_UPDATE" ]]; then
    warn "Sparkle tools not found — downloading v${SPARKLE_VERSION}…"
    SPARKLE_TXZ="/tmp/Sparkle-${SPARKLE_VERSION}.tar.xz"
    curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz" \
        -o "$SPARKLE_TXZ"
    mkdir -p "$SPARKLE_TOOLS_DIR"
    tar -xf "$SPARKLE_TXZ" -C "$SPARKLE_TOOLS_DIR"
    rm -f "$SPARKLE_TXZ"
    ok "Sparkle tools installed to scripts/sparkle-tools/"
else
    ok "Sparkle tools found"
fi

# ── Sync Info.plist version ───────────────────────────────────────────────────

step "Updating Info.plist to v${VERSION}"
BUNDLE_VERSION=$(echo "$VERSION" | tr -d '.')
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PROJECT_ROOT/BrowserPicker/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUNDLE_VERSION" "$PROJECT_ROOT/BrowserPicker/Info.plist"
ok "Info.plist → $VERSION (build $BUNDLE_VERSION)"

# ── Xcode build ──────────────────────────────────────────────────────────────

step "Regenerating Xcode project"
cd "$PROJECT_ROOT"
xcodegen generate --quiet
ok "Project generated"

step "Cleaning previous build"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    clean \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    > "$BUILD_DIR/clean.log" 2>&1 || fail "Clean failed — see $BUILD_DIR/clean.log"

ok "Clean complete"

step "Building Release"
BUILD_LOG="$BUILD_DIR/build.log"

xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CURRENT_PROJECT_VERSION="$VERSION" \
    MARKETING_VERSION="$VERSION" \
    build \
    2>&1 | tee "$BUILD_LOG" | grep -E "^(error:|warning:|note:|.*BUILD (SUCCEEDED|FAILED))" || true

if grep -q "BUILD SUCCEEDED" "$BUILD_LOG"; then
    ok "Build succeeded"
elif grep -q "BUILD FAILED" "$BUILD_LOG"; then
    echo ""
    warn "Build errors:"
    grep "error:" "$BUILD_LOG" | head -20
    fail "Build failed — full log at $BUILD_LOG"
fi

step "Locating built app"
BUILT_PRODUCTS_DIR=$(xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -showBuildSettings \
    CODE_SIGN_IDENTITY="-" \
    2>/dev/null | awk '/BUILT_PRODUCTS_DIR/{print $3; exit}')

APP_PATH="$BUILT_PRODUCTS_DIR/${APP_NAME}.app"
[[ -d "$APP_PATH" ]] || fail ".app not found at $APP_PATH"

APP_SIZE=$(du -sh "$APP_PATH" | cut -f1)
ok "App bundle: $APP_PATH ($APP_SIZE)"

step "Packaging"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

# Also create a generic BrowserPicker.zip — stable download URL that never changes.
GENERIC_ZIP_PATH="$DIST_DIR/BrowserPicker.zip"
cp "$ZIP_PATH" "$GENERIC_ZIP_PATH"

ZIP_SIZE=$(du -sh "$ZIP_PATH" | cut -f1)
ZIP_BYTES=$(stat -f%z "$ZIP_PATH")
ok "Zip created: $ZIP_SIZE"

# ── Sign + appcast ────────────────────────────────────────────────────────────

step "Signing update with EdDSA"
SIGN_OUTPUT=$("$SIGN_UPDATE" "$ZIP_PATH" 2>&1) || fail "sign_update failed — have you run generate_keys yet?\n  $SPARKLE_TOOLS_DIR/bin/generate_keys"
ED_SIGNATURE=$(echo "$SIGN_OUTPUT" | grep -o 'sparkle:edSignature="[^"]*"' | sed 's/sparkle:edSignature="//;s/"//')
[[ -n "$ED_SIGNATURE" ]] || fail "Could not parse EdDSA signature from sign_update output:\n  $SIGN_OUTPUT"
ok "Signed: ${ED_SIGNATURE:0:24}…"

step "Updating appcast.xml"
PUB_DATE=$(date -u "+%a, %d %b %Y %H:%M:%S +0000")
DOWNLOAD_URL="https://github.com/developer-pritam/browser-picker/releases/download/v${VERSION}/${ZIP_NAME}"
RELEASE_NOTES_URL="https://github.com/developer-pritam/browser-picker/releases/tag/v${VERSION}"

cat > "$APPCAST_PATH" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"
     xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
     xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>Browser Picker</title>
        <link>https://browserpicker.developerpritam.in/appcast.xml</link>
        <description>Browser Picker update feed</description>
        <language>en</language>
        <item>
            <title>Browser Picker ${VERSION}</title>
            <sparkle:releaseNotesLink>${RELEASE_NOTES_URL}</sparkle:releaseNotesLink>
            <pubDate>${PUB_DATE}</pubDate>
            <enclosure
                url="${DOWNLOAD_URL}"
                sparkle:version="${VERSION}"
                sparkle:shortVersionString="${VERSION}"
                length="${ZIP_BYTES}"
                type="application/octet-stream"
                sparkle:edSignature="${ED_SIGNATURE}"/>
        </item>
    </channel>
</rss>
EOF
ok "appcast.xml updated → docs/appcast.xml"

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo -e "────────────────────────────────────────"
echo -e "${GREEN}${BOLD}✅ Release ready${RESET}"
echo -e "   File:    ${BOLD}dist/$ZIP_NAME${RESET}"
echo -e "   Size:    $ZIP_SIZE"
echo -e "   Version: $VERSION"
echo ""
echo -e "${YELLOW}Install note for users:${RESET}"
echo "  1. Unzip and move BrowserPicker.app to /Applications"
echo "  2. Right-click → Open on first launch to bypass Gatekeeper"
echo "  3. Set as default browser in System Settings → Desktop & Dock"
echo ""

if [[ "$PUBLISH" == true ]]; then
    step "Publishing to GitHub Releases"

    command -v gh &>/dev/null || fail "GitHub CLI (gh) not found. Install with: brew install gh"
    gh auth status &>/dev/null    || fail "Not logged in to GitHub CLI. Run: gh auth login"

    TAG="v${VERSION}"
    RELEASE_TITLE="${APP_NAME} ${VERSION}"

    RELEASE_NOTES="## What's new in ${VERSION}

<!-- TODO: describe what changed in this release -->

---

### Installation
1. Download \`${ZIP_NAME}\` below
2. Unzip and move **BrowserPicker.app** to \`/Applications\`
3. **Right-click → Open** on first launch (unsigned app — Gatekeeper bypass)
4. Go to **System Settings → Desktop & Dock → Default web browser** and choose **Browser Picker**

### Requirements
- macOS 14 Sonoma or later
- Apple Silicon or Intel

---

Built with ♥ by [Pritam](https://developerpritam.in) · [Website](https://browserpicker.developerpritam.in)"

    GH_FLAGS=(
        release create "$TAG"
        "$ZIP_PATH"
        "$GENERIC_ZIP_PATH"
        --title "$RELEASE_TITLE"
        --notes "$RELEASE_NOTES"
    )

    [[ "$DRAFT" == true ]] && GH_FLAGS+=(--draft) && warn "Publishing as DRAFT"

    gh "${GH_FLAGS[@]}"

    echo ""
    echo -e "────────────────────────────────────────"
    if [[ "$DRAFT" == true ]]; then
        echo -e "${YELLOW}${BOLD}📋 Draft release created${RESET} — open GitHub Releases to publish"
    else
        echo -e "${GREEN}${BOLD}🚀 Published!${RESET}"
        REPO_URL=$(gh repo view --json url -q .url 2>/dev/null || echo "your GitHub repo")
        echo -e "   Release: ${REPO_URL}/releases/tag/${TAG}"
        echo ""
        warn "Commit the updated appcast.xml so users get the update notification:"
        echo "  git add docs/appcast.xml && git commit -m 'chore: update appcast for v${VERSION}' && git push"
    fi
    echo ""
fi
