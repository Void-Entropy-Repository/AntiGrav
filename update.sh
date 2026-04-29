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

JS_PATH=$(echo "$HTML" | grep -aoE '[a-zA-Z0-9_./-]*main[-.][a-zA-Z0-9_-]+\.js' | head -n 1)

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
TARBALL_URL=$(echo "$JS_CONTENT" | grep -aoE 'https://edgedl\.me\.gvt1\.com[^"'\'' ]+linux-x64/Antigravity\.tar\.gz' | head -n 1)

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

# Download, hash, and cleanup
echo "Downloading tarball to generate checksum..."
curl -sL "$TARBALL_URL" -o /tmp/antigravity.tar.gz
NEW_CHECKSUM=$(sha256sum /tmp/antigravity.tar.gz | awk '{print $1}')
rm -f /tmp/antigravity.tar.gz

echo "New checksum: $NEW_CHECKSUM"

# Write directly to the template
sed -i "s/^version=.*/version=$NEW_VERSION/" "$TEMPLATE_PATH"
sed -i "s|^distfiles=.*|distfiles=\"$TARBALL_URL\"|" "$TEMPLATE_PATH"
sed -i "s/^revision=.*/revision=1/" "$TEMPLATE_PATH"
sed -i "s/^checksum=.*/checksum=\"$NEW_CHECKSUM\"/" "$TEMPLATE_PATH"

echo "Template successfully updated to $NEW_VERSION and written to file."
