#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

PKG_NAME="streamvista-iptv"
APP_ID="com.streamvista.iptv"
APP_NAME="StreamVista IPTV"
BINARY_NAME="streamvista_iptv"
INSTALL_DIR="/opt/${PKG_NAME}"
MAINTAINER="${DEB_MAINTAINER:-StreamVista <support@streamvista.app>}"

VERSION_LINE="$(grep -E '^version:' pubspec.yaml | awk '{print $2}')"
VERSION="${VERSION_LINE%%+*}"
BUILD_NUMBER="${VERSION_LINE##*+}"
[ "$BUILD_NUMBER" = "$VERSION_LINE" ] && BUILD_NUMBER=1
DEB_VERSION="${VERSION}-${BUILD_NUMBER}"

case "$(uname -m)" in
  x86_64) DEB_ARCH="amd64"; FLUTTER_ARCH="x64" ;;
  aarch64) DEB_ARCH="arm64"; FLUTTER_ARCH="arm64" ;;
  *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

if ! command -v flutter >/dev/null 2>&1; then
  if [ -x "$HOME/flutter/bin/flutter" ]; then
    export PATH="$HOME/flutter/bin:$PATH"
  else
    echo "flutter not found in PATH" >&2
    exit 1
  fi
fi

if [ "${SKIP_BUILD:-0}" != "1" ]; then
  flutter pub get
  flutter build linux --release
fi

BUNDLE_DIR="build/linux/${FLUTTER_ARCH}/release/bundle"
if [ ! -x "${BUNDLE_DIR}/${BINARY_NAME}" ]; then
  echo "Release bundle not found at ${BUNDLE_DIR}" >&2
  exit 1
fi

STAGE="build/deb/${PKG_NAME}_${DEB_VERSION}_${DEB_ARCH}"
rm -rf "$STAGE"
mkdir -p "$STAGE/DEBIAN" \
         "$STAGE${INSTALL_DIR}" \
         "$STAGE/usr/bin" \
         "$STAGE/usr/share/applications" \
         "$STAGE/usr/share/metainfo"

cp -a "${BUNDLE_DIR}/." "$STAGE${INSTALL_DIR}/"
ln -s "${INSTALL_DIR}/${BINARY_NAME}" "$STAGE/usr/bin/${PKG_NAME}"

python3 - "$STAGE" "$APP_ID" <<'PY'
import os, sys
from PIL import Image
stage, app_id = sys.argv[1], sys.argv[2]
src = Image.open("icon.png").convert("RGBA")
for size in (16, 24, 32, 48, 64, 128, 256, 512):
    d = os.path.join(stage, f"usr/share/icons/hicolor/{size}x{size}/apps")
    os.makedirs(d, exist_ok=True)
    src.resize((size, size), Image.LANCZOS).save(os.path.join(d, f"{app_id}.png"))
PY

cat > "$STAGE/usr/share/applications/${APP_ID}.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=${APP_NAME}
GenericName=IPTV Player
Comment=IPTV client for authorized Xtream Codes and M3U sources
Exec=${PKG_NAME} %U
Icon=${APP_ID}
Terminal=false
Categories=AudioVideo;Video;Player;TV;
Keywords=iptv;tv;m3u;xtream;stream;
StartupWMClass=${BINARY_NAME}
StartupNotify=true
EOF

cat > "$STAGE/usr/share/metainfo/${APP_ID}.metainfo.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application">
  <id>${APP_ID}</id>
  <name>${APP_NAME}</name>
  <summary>IPTV client for authorized Xtream Codes and M3U sources</summary>
  <metadata_license>CC0-1.0</metadata_license>
  <launchable type="desktop-id">${APP_ID}.desktop</launchable>
  <releases>
    <release version="${VERSION}"/>
  </releases>
</component>
EOF

INSTALLED_SIZE="$(du -sk --exclude=DEBIAN "$STAGE" | awk '{print $1}')"

cat > "$STAGE/DEBIAN/control" <<EOF
Package: ${PKG_NAME}
Version: ${DEB_VERSION}
Section: video
Priority: optional
Architecture: ${DEB_ARCH}
Installed-Size: ${INSTALLED_SIZE}
Maintainer: ${MAINTAINER}
Depends: libgtk-3-0t64 | libgtk-3-0, libmpv2 | libmpv1, libsecret-1-0, libstdc++6, libc6
Description: ${APP_NAME}
 IPTV client for authorized Xtream Codes and M3U sources,
 with live TV, movies and series playback powered by mpv.
EOF

cat > "$STAGE/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database -q /usr/share/applications || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor || true
fi
exit 0
EOF
cp "$STAGE/DEBIAN/postinst" "$STAGE/DEBIAN/postrm"
chmod 0755 "$STAGE/DEBIAN/postinst" "$STAGE/DEBIAN/postrm"

find "$STAGE" -type d -exec chmod 0755 {} +
find "$STAGE" -path "$STAGE/DEBIAN" -prune -o -type f -exec chmod 0644 {} +
chmod 0644 "$STAGE/DEBIAN/control"
chmod 0755 "$STAGE${INSTALL_DIR}/${BINARY_NAME}"

mkdir -p dist
OUT="dist/${PKG_NAME}_${DEB_VERSION}_${DEB_ARCH}.deb"
dpkg-deb --root-owner-group --build "$STAGE" "$OUT"
echo "Built: ${OUT}"
