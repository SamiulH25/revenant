#!/usr/bin/env bash
# Runs Suwayomi-Server in the foreground with Revenant's settings, for
# development: the app attaches to it instead of starting its own, so
# repeated app launches skip the server's start-up time.
set -euo pipefail
share="${XDG_DATA_HOME:-$HOME/.local/share}/revenant"
exec java -Djava.awt.headless=true \
  -Dsuwayomi.tachidesk.config.server.rootDir="$share/data" \
  -Dsuwayomi.tachidesk.config.server.ip=127.0.0.1 \
  -Dsuwayomi.tachidesk.config.server.port=4577 \
  -Dsuwayomi.tachidesk.config.server.webUIEnabled=false \
  -Dsuwayomi.tachidesk.config.server.initialOpenInBrowserEnabled=false \
  -Dsuwayomi.tachidesk.config.server.systemTrayEnabled=false \
  -jar "$share/server/Suwayomi-Server.jar"
