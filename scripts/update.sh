#!/bin/bash
set -e

# Target can be 'ide', 'app', 'cli', or 'all' (default)
TARGET=${1:-"all"}

echo "Fetching HTML payload..."
HTML=$(curl -sL --compressed \
  -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
  -A "Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0" \
  "https://antigravity.google/download/linux")

JS_PATH=$(echo "$HTML" | grep -aoE '[a-zA-Z0-9_./-]*main[-.][a-zA-Z0-9_-]+\.js' | grep -v 'polyfill\|legacy' | head -n 1)
[ -z "$JS_PATH" ] && { echo "Error: Could not find main JS file."; exit 1; }

JS_URL=$(echo "$JS_PATH" | grep -q "^http" && echo "$JS_PATH" || echo "https://antigravity.google/${JS_PATH#/}")
echo "Fetching JS bundle from: $JS_URL"

# Download the JS bundle ONCE into memory for all variants to parse
JS_CONTENT=$(curl -sL --compressed -A "Mozilla/5.0" "$JS_URL")


# --- CORE UPDATE LOGIC ---
update_variant() {
    local VARIANT_NAME=$1
    local TEMPLATE_PATH=$2
    local REGEX=$3
    local SUFFIX=$4
    local ICON_URL=$5
    local ICON_CHECKSUM=$6

    printf "\n----------------------------------------\n"
    echo "Evaluating $VARIANT_NAME..."

    if [ ! -f "$TEMPLATE_PATH" ]; then
        echo "Skipping... '$TEMPLATE_PATH' not found in current directory."
        return 0
    fi

    CURRENT_VERSION=$(grep '^version=' "$TEMPLATE_PATH" | cut -d= -f2 | tr -d ' \r\n"')

    # Extract the specific tarball URL using the strict variant regex
    TARBALL_URL=$(echo "$JS_CONTENT" | grep -aoE "$REGEX" | sort -V | tail -n 1)

    if [ -z "$TARBALL_URL" ]; then
        echo "Error: Could not extract URL for $VARIANT_NAME from JS bundle."
        return 1
    fi

    NEW_VERSION=$(echo "$TARBALL_URL" | awk -F'/stable/' '{print $2}' | cut -d'-' -f1)

    if [ "$CURRENT_VERSION" = "$NEW_VERSION" ]; then
        echo "✓ $VARIANT_NAME is up to date (v$CURRENT_VERSION)."
        return 0
    fi

    echo "Update required! Bumping $VARIANT_NAME v$CURRENT_VERSION -> v$NEW_VERSION"
    echo "Downloading tarball to generate new checksum..."

    curl -sL "$TARBALL_URL" -o "/tmp/ag-${VARIANT_NAME}.tar.gz"
    NEW_CHECKSUM=$(sha256sum "/tmp/ag-${VARIANT_NAME}.tar.gz" | awk '{print $1}')
    rm -f "/tmp/ag-${VARIANT_NAME}.tar.gz"

    # Update version and reset revision
    sed -i "s/^version=.*/version=$NEW_VERSION/" "$TEMPLATE_PATH"
    sed -i "s/^revision=.*/revision=1/" "$TEMPLATE_PATH"

    # Purge old distfiles and checksum blocks completely
    sed -i '/^distfiles="/,/"$/d' "$TEMPLATE_PATH"
    sed -i '/^checksum="/,/"$/d' "$TEMPLATE_PATH"

    # Swap the hardcoded version string back to \${version} for template standards
    TEMPLATE_URL="${TARBALL_URL//$NEW_VERSION/\\\${version\}}"

    # Inject immediately after 'homepage=' to preserve the native Void template order
    if [ -n "$ICON_URL" ] && [ -n "$ICON_CHECKSUM" ]; then
        sed -i "/^homepage=.*/a distfiles=\"$TEMPLATE_URL>$SUFFIX $ICON_URL\"\nchecksum=\"$NEW_CHECKSUM $ICON_CHECKSUM\"" "$TEMPLATE_PATH"
    else
        # Fallback for CLI which doesn't have an icon mapping
        sed -i "/^homepage=.*/a distfiles=\"$TEMPLATE_URL>$SUFFIX\"\nchecksum=\"$NEW_CHECKSUM\"" "$TEMPLATE_PATH"
    fi

    echo "$VARIANT_NAME template successfully written."
}


# --- REGEX DEFINITIONS ---
REGEX_IDE='https://edgedl\.me\.gvt1\.com[^"'\'' ]+linux-[a-zA-Z0-9_-]+/Antigravity%20IDE\.tar\.gz'
REGEX_APP='https://edgedl\.me\.gvt1\.com[^"'\'' ]+linux-[a-zA-Z0-9_-]+/Antigravity\.tar\.gz'
REGEX_CLI='https://edgedl\.me\.gvt1\.com[^"'\'' ]+linux-[a-zA-Z0-9_-]+/Antigravity-CLI\.tar\.gz'

# --- STATIC ASSET DEFINITIONS ---
SHARED_ICON_URL="https://raw.githubusercontent.com/Void-Entropy-Repository/AntiGrav/main/assets/icon.png"
SHARED_ICON_HASH="b27f0e4a6f14f491ba31bb24533a1f43c677362b12a0744a53fdd09d7c785317"


# --- EXECUTION ROUTING ---
if [ "$TARGET" = "ide" ] || [ "$TARGET" = "all" ]; then
    update_variant "IDE" "template-ide" "$REGEX_IDE" "antigravity-ide-\\\${version}.tar.gz" "$SHARED_ICON_URL>antigravity-ide.png" "$SHARED_ICON_HASH"
fi

if [ "$TARGET" = "app" ] || [ "$TARGET" = "all" ]; then
    update_variant "Standalone App" "template-app" "$REGEX_APP" "antigravity-\\\${version}.tar.gz" "$SHARED_ICON_URL>antigravity.png" "$SHARED_ICON_HASH"
fi

if [ "$TARGET" = "cli" ] || [ "$TARGET" = "all" ]; then
    update_variant "CLI Engine" "template-cli" "$REGEX_CLI" "antigravity-cli-\\\${version}.tar.gz" "" ""
fi

printf "\n----------------------------------------\n"
echo "Operation complete."
