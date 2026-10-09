#!/usr/bin/env bash
# Install (or remove) Edge Dash for the current user: renders the systemd user units
# with this checkout's path, enables them, and on KDE Plasma applies a KWin rule and
# maps the Edge touchscreen to its output.
#
#   ./install.sh [--output=DP-4] [--theme=tokyo] [--no-touch] [--no-start]
#   ./install.sh --uninstall
set -euo pipefail

DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
CFG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/edge-dash"
OUTPUT="" THEME="" TOUCH=1 START=1 UNINSTALL=0
TOUCH_NAME="wch.cn TouchScreen"   # the Edge's USB digitizer (27c0:0859)

for a in "$@"; do
  case "$a" in
    --output=*) OUTPUT="${a#--output=}" ;;
    --theme=*) THEME="${a#--theme=}" ;;
    --no-touch) TOUCH=0 ;;
    --no-start) START=0 ;;
    --uninstall) UNINSTALL=1 ;;
    -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

say() { printf '\033[1;35m•\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*" >&2; }
need() { command -v "$1" >/dev/null 2>&1 || { warn "missing: $1 ($2)"; MISSING=1; }; }

if (( UNINSTALL )); then
  systemctl --user disable --now edge-dash.service edge-schedule.timer 2>/dev/null || true
  rm -f "$UNIT_DIR"/edge-dash.service "$UNIT_DIR"/edge-schedule.service "$UNIT_DIR"/edge-schedule.timer
  systemctl --user daemon-reload
  if command -v kwriteconfig6 >/dev/null; then
    kwriteconfig6 --file kwinrulesrc --group edge-dash --key title --delete 2>/dev/null || true
    rules=$(kreadconfig6 --file kwinrulesrc --group General --key rules 2>/dev/null | tr ',' '\n' | grep -vx edge-dash | paste -sd, -)
    kwriteconfig6 --file kwinrulesrc --group General --key rules "$rules"
    qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null || true
  fi
  say "removed units and KWin rule; config in $CFG_DIR and the touch mapping were left alone"
  exit 0
fi

# ---- dependencies ------------------------------------------------------------
MISSING=0
need qml6 "qt6-declarative"
need uv "https://docs.astral.sh/uv/ — runs fetch_schedule.py with its deps"
[[ -d /usr/lib/qt6/qml/QtWebEngine || -d /usr/lib64/qt6/qml/QtWebEngine || -d /usr/lib/x86_64-linux-gnu/qt6/qml/QtWebEngine ]] \
  || { warn "QtWebEngine QML module not found (qt6-webengine)"; MISSING=1; }
(( MISSING )) && { warn "install the missing packages and re-run"; exit 1; }

# ---- config ------------------------------------------------------------------
mkdir -p "$CFG_DIR" && chmod 700 "$CFG_DIR"
if [[ ! -e "$CFG_DIR/calendars.toml" ]]; then
  install -m 600 "$DIR/calendars.example.toml" "$CFG_DIR/calendars.toml"
  say "created $CFG_DIR/calendars.toml — put your ICS URLs in it"
fi

# ---- systemd user units --------------------------------------------------------
mkdir -p "$UNIT_DIR"
KIOSK_ARGS=""; [[ -n "$OUTPUT" ]] && KIOSK_ARGS+=" --output=$OUTPUT"; [[ -n "$THEME" ]] && KIOSK_ARGS+=" --theme=$THEME"
for u in edge-dash.service edge-schedule.service edge-schedule.timer; do
  rm -f "$UNIT_DIR/$u"   # may be a symlink from an older install; never write through it
  sed -e "s|@DIR@|$DIR|g" -e "s|@UV@|$(command -v uv)|g" -e "s|@KIOSK_ARGS@|$KIOSK_ARGS|g" \
      "$DIR/systemd/$u" > "$UNIT_DIR/$u"
done
systemctl --user daemon-reload
say "rendered units into $UNIT_DIR"

# ---- KDE Plasma extras ---------------------------------------------------------
if [[ "${XDG_CURRENT_DESKTOP:-}" == *KDE* ]] && command -v kwriteconfig6 >/dev/null; then
  rules=$(kreadconfig6 --file kwinrulesrc --group General --key rules 2>/dev/null || true)
  [[ ",$rules," == *,edge-dash,* ]] || kwriteconfig6 --file kwinrulesrc --group General --key rules "${rules:+$rules,}edge-dash"
  for kv in "Description=Edge Dash kiosk" "title=Edge Dash" "titlematch=1" \
            "skiptaskbar=true" "skiptaskbarrule=2" "skipswitcher=true" "skipswitcherrule=2" "skippager=true" "skippagerrule=2"; do
    kwriteconfig6 --file kwinrulesrc --group edge-dash --key "${kv%%=*}" "${kv#*=}"
  done
  qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null || true
  say "KWin rule: hide the kiosk from taskbar / switcher / pager"

  if (( TOUCH )) && command -v qdbus6 >/dev/null; then
    # Find the Edge's output (by EDID name) unless given, then bind the digitizer to it.
    if [[ -z "$OUTPUT" ]]; then
      for e in /sys/class/drm/card*-*/edid; do
        if strings "$e" 2>/dev/null | grep -q "XENEON EDGE"; then
          OUTPUT="$(basename "$(dirname "$e")")"; OUTPUT="${OUTPUT#card*-}"; break
        fi
      done
    fi
    node=""
    for d in $(qdbus6 org.kde.KWin /org/kde/KWin/InputDevice org.kde.KWin.InputDeviceManager.devicesSysNames 2>/dev/null); do
      n=$(qdbus6 org.kde.KWin "/org/kde/KWin/InputDevice/$d" org.freedesktop.DBus.Properties.Get org.kde.KWin.InputDevice name 2>/dev/null || true)
      t=$(qdbus6 org.kde.KWin "/org/kde/KWin/InputDevice/$d" org.freedesktop.DBus.Properties.Get org.kde.KWin.InputDevice touch 2>/dev/null || true)
      [[ "$n" == "$TOUCH_NAME" && "$t" == "true" ]] && { node="$d"; break; }
    done
    if [[ -n "$node" && -n "$OUTPUT" ]]; then
      # Setting it over D-Bus makes KWin persist OutputName+OutputUuid itself; editing kcminputrc by hand is ignored.
      qdbus6 org.kde.KWin "/org/kde/KWin/InputDevice/$node" org.freedesktop.DBus.Properties.Set org.kde.KWin.InputDevice outputName "$OUTPUT" \
        && say "touchscreen '$TOUCH_NAME' mapped to $OUTPUT" || warn "could not map touchscreen; use System Settings → Mouse & Touchpad → Touchscreen"
    else
      warn "touchscreen or Edge output not found — map it in System Settings → Mouse & Touchpad → Touchscreen"
    fi
  fi
fi

# ---- go ------------------------------------------------------------------------
systemctl --user enable edge-dash.service edge-schedule.timer >/dev/null
if (( START )); then
  systemctl --user start edge-schedule.service || warn "schedule refresh failed (no URLs yet?) — see: journalctl --user -u edge-schedule"
  systemctl --user restart edge-dash.service
  say "running. logs: journalctl --user -u edge-dash -u edge-schedule -f"
else
  say "enabled; start with: systemctl --user start edge-schedule edge-dash"
fi
