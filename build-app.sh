#!/bin/bash
# Builds Ticker.app — required for URL scheme registration and Login Items.
# The CLI binary (ticker --send etc.) stays via: swift build -c release
set -e

APP="Ticker.app"
CONTENTS="$APP/Contents"

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

swift build -c release 2>&1

cp .build/release/ticker "$CONTENTS/MacOS/ticker"
cp Info.plist "$CONTENTS/Info.plist"
cp icons/ticker.icns "$CONTENTS/Resources/ticker.icns"

# Ad-hoc sign — required for URL scheme registration
codesign --force --deep --sign - "$APP"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo "→ $APP"
echo ""
echo "Symlink CLI: ln -sf \"\$(pwd)/$APP/Contents/MacOS/ticker\" ~/bin/ticker"
