#!/usr/bin/env bash
#
# Reset local Claude Desktop and Claude Code identity stores on macOS.
#
# Preview by default: it prints what it found and deletes nothing until you
# choose 1. The next launch recreates machineID, userID, ant-did, the device
# registry, telemetry salts, and the Chromium storage. Local chats are kept.
#
# The Claude.app itself, macOS locale, timezone, public IP, and Safari/Chrome
# cookies for claude.ai are outside this script.
#
# Usage:
#   bash reset-claude-identity.command            # preview, then prompts 1/2
#   bash reset-claude-identity.command --apply    # delete without the prompt
#
# NOTE: written and syntax-checked on Windows, not yet run on real macOS.
# Keep it in PREVIEW first and eyeball the target list before choosing 1.

set -u

APPLY=0
for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
  esac
done

HOME_DIR="${HOME%/}"
CLAUDE_HOME="$HOME_DIR/.claude"
APPSUP="$HOME_DIR/Library/Application Support/Claude"
APPSUP_3P="$HOME_DIR/Library/Application Support/Claude-3p"

# ---- helpers ---------------------------------------------------------------

have() { command -v "$1" >/dev/null 2>&1; }

PY=""
if have python3; then PY="python3"; elif have python; then PY="python"; fi

json_get() {
  # json_get <file> <top-level-key>
  [ -f "$1" ] || { printf ''; return; }
  if [ -n "$PY" ]; then
    "$PY" - "$1" "$2" <<'EOF' 2>/dev/null
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8-sig") as f:
        d = json.load(f)
    v = d.get(sys.argv[2], "")
    print(v if isinstance(v, str) else ("" if v is None else str(v)))
except Exception:
    print("")
EOF
  else
    sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$1" | head -n 1
  fi
}

prefix() {
  local v="$1"
  v="${v//[$'\t\r\n ']/}"
  if [ -z "$v" ]; then printf '(empty)'; return; fi
  if [ "${#v}" -le 12 ]; then printf '%s' "$v"; return; fi
  printf '%s...%s' "${v:0:8}" "${v: -4}"
}

size_of() {
  if [ -e "$1" ]; then du -sh "$1" 2>/dev/null | cut -f1; else printf '-'; fi
}

show_markers() {
  local cli="$HOME_DIR/.claude.json"
  if [ -f "$cli" ]; then
    printf '  CLI machineID : %s\n' "$(prefix "$(json_get "$cli" machineID)")"
    printf '  CLI userID    : %s\n' "$(prefix "$(json_get "$cli" userID)")"
  else
    printf '  CLI .claude.json: absent\n'
  fi
  if [ -f "$APPSUP/ant-did" ]; then
    printf '  ant-did       : %s\n' "$(prefix "$(cat "$APPSUP/ant-did" 2>/dev/null)")"
  else
    printf '  ant-did       : absent\n'
  fi
  if [ -f "$APPSUP/remote-control-state.json" ]; then
    printf '  telemetrySalt : %s\n' "$(prefix "$(json_get "$APPSUP/remote-control-state.json" telemetrySalt)")"
  fi
  if [ -f "$APPSUP/ccd-ids.json" ]; then
    printf '  ccd salt      : %s\n' "$(prefix "$(json_get "$APPSUP/ccd-ids.json" salt)")"
  fi
}

# ---- build the target list -------------------------------------------------

TARGETS=()
add_target() {
  local p="$1"
  [ -e "$p" ] || return 0
  # safety: only ever touch paths under $HOME or the per-user temp dir
  case "$p" in
    "$HOME_DIR"/*) : ;;
    "${TMPDIR%/}"/*|/tmp/*) : ;;
    *) return 0 ;;
  esac
  TARGETS+=("$p")
}

# CLI (~/.claude): identity, not chats
for n in ".credentials.json" "backups" "cache" "ide" "session-env"; do
  add_target "$CLAUDE_HOME/$n"
done
# CLI config + its backups / temp copies
add_target "$HOME_DIR/.claude.json"
for f in "$HOME_DIR"/.claude.json.*; do add_target "$f"; done

# Desktop app (~/Library/Application Support/Claude): identity + salts
for n in \
  "ant-did" "ant-device-registry.json" "remote-control-state.json" "ccd-ids.json" "config.json" \
  "Preferences" "Local State" "DIPS" "DIPS-wal" "SharedStorage" "SharedStorage-wal" \
  "InterestGroups" "InterestGroups-wal" "declarative_performance_observer.db" \
  "declarative_performance_observer.db-journal" "fcache"; do
  add_target "$APPSUP/$n"
done
# Desktop Chromium storage
for n in \
  "Network" "Local Storage" "Session Storage" "IndexedDB" "WebStorage" "shared_proto_db" \
  "sentry" "logs" "Cache" "Code Cache" "GPUCache" "DawnGraphiteCache" "DawnWebGPUCache" \
  "blob_storage" "Crashpad" "Partitions" "File System" "VideoDecodeStats" "Shared Dictionary" \
  "Service Worker" "Storage"; do
  add_target "$APPSUP/$n"
done

# 3P data tree, logs and caches
add_target "$APPSUP_3P"
add_target "$HOME_DIR/Library/Logs/Claude"
add_target "$HOME_DIR/Library/Logs/Claude-3p"
add_target "$HOME_DIR/Library/Caches/claude-cli-nodejs"
add_target "$HOME_DIR/Library/Caches/Claude"
for d in "$HOME_DIR"/Library/Caches/com.anthropic.claude*; do add_target "$d"; done

# per-session cache-break files in the temp dir
for base in "${TMPDIR%/}/claude" "/tmp/claude"; do
  if [ -d "$base" ]; then
    for f in "$base"/cache-break-state-*.json; do add_target "$f"; done
  fi
done

# ---- kept (chats) ----------------------------------------------------------

KEPT=(
  "$CLAUDE_HOME/projects"
  "$CLAUDE_HOME/sessions"
  "$CLAUDE_HOME/file-history"
  "$CLAUDE_HOME/settings.json"
  "$APPSUP/claude-code-sessions"
  "$APPSUP/local-agent-mode-sessions"
)

# ---- report ----------------------------------------------------------------

echo
echo "Claude local identity reset (macOS)"
echo "-----------------------------------"
if [ "$APPLY" -eq 1 ]; then
  echo "Mode: APPLY (files will be deleted)"
else
  echo "Mode: PREVIEW (deletion starts only after you choose 1)"
fi

echo
echo "Current markers:"
show_markers

echo
echo "Targets:"
if [ "${#TARGETS[@]}" -eq 0 ]; then
  echo "  nothing found"
else
  for t in "${TARGETS[@]}"; do
    printf '  [%6s]  %s\n' "$(size_of "$t")" "$t"
  done
fi

echo
echo "Kept (local chats):"
kept_any=0
for k in "${KEPT[@]}"; do
  if [ -e "$k" ]; then kept_any=1; printf '  [%6s]  %s\n' "$(size_of "$k")" "$k"; fi
done
[ "$kept_any" -eq 0 ] && echo "  none found"

echo
echo "Also left in place:"
echo "  Claude.app (the app itself)"
echo "  macOS locale, timezone, public IP"
echo "  Safari/Chrome cookies for claude.ai"
echo "  claude_desktop_config.json will be edited, not deleted"
echo
echo "Login and device IDs are removed. Local chat transcripts stay on disk."

# ---- prompt ----------------------------------------------------------------

if [ "$APPLY" -ne 1 ]; then
  echo
  while true; do
    printf 'Type 1 to delete the identifiers, or 2 to exit: '
    if ! read -r answer; then answer=2; fi
    case "$answer" in
      1) break ;;
      2|"") echo "Exit. Nothing deleted."; exit 0 ;;
      *) echo "Please type 1 or 2." ;;
    esac
  done
fi

# ---- stop Claude -----------------------------------------------------------

echo
echo "Stopping Claude..."
osascript -e 'tell application "Claude" to quit' >/dev/null 2>&1 || true
sleep 1
# node CLI and any leftover app processes
pkill -f 'Claude.app/Contents/MacOS/Claude' 2>/dev/null || true
pkill -f '@anthropic-ai/claude' 2>/dev/null || true
pkill -f 'claude-code' 2>/dev/null || true
sleep 2

# ---- delete ----------------------------------------------------------------

remove_target() {
  local p="$1"
  [ -e "$p" ] || [ -L "$p" ] || return 0
  if [ -L "$p" ]; then
    echo "SKIP symlink: $p"
    return 1
  fi
  rm -rf -- "$p"
  [ -e "$p" ] && return 1 || return 0
}

FAILED=()
for t in "${TARGETS[@]}"; do
  echo "Removing $t"
  remove_target "$t" || FAILED+=("$t")
done

# retry once for anything still locked
if [ "${#FAILED[@]}" -gt 0 ]; then
  sleep 1
  RETRY=("${FAILED[@]}")
  FAILED=()
  for t in "${RETRY[@]}"; do
    remove_target "$t" || FAILED+=("$t")
  done
fi

# ---- edit claude_desktop_config.json (strip device fields) -----------------

CFG="$APPSUP/claude_desktop_config.json"
if [ -f "$CFG" ] && [ -n "$PY" ]; then
  echo "Editing claude_desktop_config.json"
  "$PY" - "$CFG" <<'EOF' 2>/dev/null || true
import json, sys
p = sys.argv[1]
try:
    with open(p, encoding="utf-8-sig") as f:
        cfg = json.load(f)
    prefs = cfg.get("preferences")
    if isinstance(prefs, dict):
        for k in list(prefs.keys()):
            if k == "remoteToolsDeviceName" or k.endswith("ByAccount"):
                prefs.pop(k, None)
    with open(p, "w", encoding="utf-8") as f:
        json.dump(cfg, f, ensure_ascii=False, indent=2)
except Exception:
    pass
EOF
fi

# ---- Keychain login item (best effort) -------------------------------------

if have security; then
  security delete-generic-password -s "Claude Code-credentials" >/dev/null 2>&1 || true
  security delete-generic-password -l "Claude Code" >/dev/null 2>&1 || true
fi

# ---- result ----------------------------------------------------------------

echo
echo "Markers after wipe:"
show_markers

echo
if [ "${#FAILED[@]}" -eq 0 ]; then
  echo "Done. The next Claude launch creates new local IDs."
  exit 0
fi
echo "Still present:"
for t in "${FAILED[@]}"; do echo "  $t"; done
echo "Fully quit Claude and run this again."
exit 2
