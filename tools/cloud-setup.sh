#!/usr/bin/env bash
# Provisions a Claude Code cloud container (Ubuntu 24.04) for Revenant work:
# Qt 6 from conda-forge (apt only has 6.4), Xvfb + Mesa for headless
# rendering, and the Suwayomi-Server jar where Revenant looks for it.
# Paste into the environment's setup script, or run it by hand.
set -euo pipefail

SUWAYOMI_VERSION=${SUWAYOMI_VERSION:-v2.4.2366}
QT_VERSION=${QT_VERSION:-6.12}

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq ninja-build cmake g++ openjdk-21-jre-headless xvfb xauth \
  libgl1-mesa-dev libegl1 libgl1-mesa-dri libxkbcommon0 libxkbcommon-x11-0 \
  libfontconfig1 libfreetype6 libdbus-1-3 libxcb-cursor0 libxcb-icccm4 \
  libxcb-image0 libxcb-keysyms1 libxcb-randr0 libxcb-render-util0 \
  libxcb-shape0 libxcb-xinerama0 libxcb-xkb1 libx11-xcb1

# Qt (configure with -DCMAKE_PREFIX_PATH=/opt/qt6)
if [ ! -d /opt/qt6/lib/cmake/Qt6Quick ]; then
  mkdir -p /opt/micromamba/bin
  curl -fsSL -o /opt/micromamba/bin/micromamba \
    https://github.com/mamba-org/micromamba-releases/releases/latest/download/micromamba-linux-64
  chmod +x /opt/micromamba/bin/micromamba
  MAMBA_ROOT_PREFIX=/opt/micromamba /opt/micromamba/bin/micromamba create -y -q \
    -p /opt/qt6 -c conda-forge "qt6-main=${QT_VERSION}" libwebp
fi

# Suwayomi-Server. The app's own download uses the GitHub API, which the
# cloud proxy refuses; direct release-asset URLs are allowed.
server_dir="$HOME/.local/share/revenant/server"
if [ ! -f "$server_dir/Suwayomi-Server.jar" ]; then
  tmp=$(mktemp -d)
  base="https://github.com/Suwayomi/Suwayomi-Server/releases/download/${SUWAYOMI_VERSION}"
  jar="Suwayomi-Server-${SUWAYOMI_VERSION}.jar"
  curl -fsSL -o "$tmp/Checksums.sha256" "$base/Checksums.sha256"
  curl -fsSL -o "$tmp/$jar" "$base/$jar"
  (cd "$tmp" && grep " ${jar}\$" Checksums.sha256 | sha256sum -c -)
  mkdir -p "$server_dir"
  mv "$tmp/$jar" "$server_dir/Suwayomi-Server.jar"
  rm -rf "$tmp"
fi
