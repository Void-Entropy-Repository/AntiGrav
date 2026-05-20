#!/bin/sh
set -e

TEMPLATE_PATH=${1:-"template"}

if [ ! -f "$TEMPLATE_PATH" ]; then
    echo "Error: Template not found at '$TEMPLATE_PATH'."
    exit 1
fi

# Clean current version extraction
CURRENT_VERSION=$(grep '^version=' "$TEMPLATE_PATH" | cut -d= -f2 | tr -d ' \r\n"')
echo "Current VER version: $CURRENT_VERSION"

echo "Fetching HTML..."
HTML=$(curl -sL --compressed \
  -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
  -A "Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0" \
  "https://antigravity.google/download/linux")

JS_PATH=$(echo "$HTML" | grep -aoE '[a-zA-Z0-9_./-]*main[-.][a-zA-Z0-9_-]+\.js' | grep -v 'polyfill\|legacy' | head -n 1)

if [ -z "$JS_PATH" ]; then
    echo "Error: Could not find main JS file in HTML."
    exit 1
fi

if echo "$JS_PATH" | grep -q "^http"; then
    JS_URL="$JS_PATH"
elif echo "$JS_PATH" | grep -q "^/"; then
    JS_URL="https://antigravity.google${JS_PATH}"
else
    JS_URL="https://antigravity.google/${JS_PATH}"
fi

echo "Fetching JS from: $JS_URL"

JS_CONTENT=$(curl -sL --compressed -A "Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0" "$JS_URL")
TARBALL_URL=$(echo "$JS_CONTENT" | grep -aoE 'https://edgedl\.me\.gvt1\.com[^"'\'' ]+linux-[a-zA-Z0-9_-]+/[^"'\'' ]+\.tar\.gz' | sort -V | tail -n 1)

if [ -z "$TARBALL_URL" ]; then
    echo "Error: Could not extract tarball URL from JS bundle."
    exit 1
fi

NEW_VERSION=$(echo "$TARBALL_URL" | awk -F'/stable/' '{print $2}' | cut -d'-' -f1)
echo "Found upstream version: $NEW_VERSION"

if [ "$CURRENT_VERSION" = "$NEW_VERSION" ]; then
    echo "Up to date. No action required."
    exit 0
fi

echo "Update required! Bumping $CURRENT_VERSION -> $NEW_VERSION"

echo "Downloading tarball to generate checksum..."
curl -sL "$TARBALL_URL" -o /tmp/antigravity.tar.gz
NEW_CHECKSUM=$(sha256sum /tmp/antigravity.tar.gz | awk '{print $1}')
rm -f /tmp/antigravity.tar.gz
echo "New checksum: $NEW_CHECKSUM"

# Static variables for the manually hosted asset
ICON_URL="https://raw.githubusercontent.com/Void-Entropy-Repository/AntiGrav/main/assets/icon.png>antigravity.png"
ICON_CHECKSUM="b27f0e4a6f14f491ba31bb24533a1f43c677362b12a0744a53fdd09d7c785317"

# Update version and reset revision
sed -i "s/^version=.*/version=$NEW_VERSION/" "$TEMPLATE_PATH"
sed -i "s/^revision=.*/revision=1/" "$TEMPLATE_PATH"

# 1. Safely delete the old multi-line blocks (from opening quote to closing quote)
sed -i '/^distfiles="/,/"$/d' "$TEMPLATE_PATH"
sed -i '/^checksum="/,/"$/d' "$TEMPLATE_PATH"

# 2. Re-insert the updated multi-line blocks right before the 'repository=' line
sed -i "/^repository=/i distfiles=\"$TARBALL_URL\"\n $ICON_URL\"\nchecksum=\"$NEW_CHECKSUM\"\n $ICON_CHECKSUM\"\n" "$TEMPLATE_PATH"

echo "Template successfully updated to $NEW_VERSION and written to file."
