#!/usr/bin/env bash
# Launch the Edge Dash kiosk with the stock Qt 6 "qml6" runtime (no build step).
#   ./edge-dash.sh [--output=DP-4] [--theme=tokyo] [--hold=YYYY-MM-DD] [--shot]
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-wayland}"
export QT_FORCE_STDERR_LOGGING=1          # Qt otherwise logs to journald only when stderr is not a tty
# --expose-gc: QtWebEngine's V8 never runs garbage collection by itself (QTBUG-150024, fixed
# upstream after 6.11.2), so index.html calls window.gc() every 30 s to keep the renderer flat.
export QTWEBENGINE_CHROMIUM_FLAGS="${QTWEBENGINE_CHROMIUM_FLAGS:---disable-logging --js-flags=--expose-gc}"
exec qml6 kiosk.qml -- "$@"
