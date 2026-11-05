#!/usr/bin/env bash
# Headless run for screenshots/smoke tests: ./tools/shoot.sh script.txt
# Screenshot paths in the script are relative to the current directory.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
export __EGL_VENDOR_LIBRARY_DIRS=${__EGL_VENDOR_LIBRARY_DIRS:-/usr/share/glvnd/egl_vendor.d}
exec xvfb-run -a -s "-screen 0 1920x1200x24" env \
  QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=rhi QSG_RHI_BACKEND=opengl \
  LC_ALL=C.UTF-8 REVENANT_SCRIPT="$1" "$here/build/revenant"
