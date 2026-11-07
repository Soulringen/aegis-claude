#!/usr/bin/env bash
#
# Reset local Claude Desktop and Claude Code identity stores on macOS.
#
# Preview by default: it prints what it found and deletes nothing until you
# choose 1. The next launch recreates machineID, userID, ant-did, the device
# registry, telemetry salts, and the Chromium storage. Local chats and
# project memory (MEMORY.md) are kept.
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
  if [ -f "$CLAUDE_HOME/.claude.json" ]; then
    printf '  .claude/.claude.json machineID: %s\n' "$(prefix "$(json_get "$CLAUDE_HOME/.claude.json" machineID)")"
  fi
  if [ -f "$CLAUDE_HOME/policy-limits.json.stamp.json" ]; then
    printf '  policy stamp  : %s\n' "$(prefix "$(json_get "$CLAUDE_HOME/policy-limits.json.stamp.json" identity)")"
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

# CLI (~/.claude): identity, telemetry, policy stamps and caches (not chats or project memory)
for n in \
  ".claude.json" ".credentials.json" ".last-cleanup" \
  "backups" "cache" "ide" "session-env" "telemetry" "shell-snapshots" "statsig" "debug" \
  "policy-limits.json" "policy-limits.json.stamp.json" "remote-settings.json"; do
  add_target "$CLAUDE_HOME/$n"
done
for f in "$CLAUDE_HOME"/.claude.json.*; do add_target "$f"; done

# CLI config + its backups / temp copies
add_target "$HOME_DIR/.claude.json"
for f in "$HOME_DIR"/.claude.json.*; do add_target "$f"; done

# Desktop app (~/Library/Application Support/Claude): identity + salts + account-scoped stores
for n in \
  "ant-did" "ant-device-registry.json" "ant-device-key-generation.json" \
  "remote-control-state.json" "ccd-ids.json" "ccd-session-presets.json" "ccd-session-secrets" \
  "config.json" "config.json.journal" "plan-usage-history.json" \
  "buddy-tokens.json" "ssh-remote-server-state.json" \
  "cowork-enabled-cli-ops.json" "cowork-memory-resets.json" "cowork-clientdata-cache.json" \
  "cowork-deletion-outbox.json" "cowork-gb-cache.json" "cowork-plugin-mcp-shadow.json" \
  "cowork-policy-limits-cache.json" "cowork-wipe-record.json" "cowork_account_settings.json" "cowork_settings.json" \
  "extensions-blocklist.json" "mcp-user-tool-toggles.json" "git-worktrees.json" \
  "memory-migration-state.json" "remote-session-spaces.json" "restored-ids.json" \
  "local-session-state.json" "local-sessions.json" "states-10m.json" "stats-cache.json" \
  "projects-sent-to-a-session-host.json" "msal-cache.json" "msal_token_cache.json" "tokens.json" \
  "window-state.json" "design" \
  "spaces-present" "rpm" "plugin-list" "git-shadow" "pending-uploads" "preview-last-frames" "side-session-notes" \
  "Preferences" "Local State" "DIPS" "DIPS-wal" "SharedStorage" "SharedStorage-wal" \
  "InterestGroups" "InterestGroups-wal" "declarative_performance_observer.db" \
  "declarative_performance_observer.db-journal" "fcache"; do
  add_target "$APPSUP/$n"
done
for f in "$APPSUP"/config.json.corrupt-* "$APPSUP"/memory-migration-state.json.corrupt-*; do
  add_target "$f"
done

# Desktop Chromium storage
for n in \
  "Network" "Local Storage" "Session Storage" "IndexedDB" "WebStorage" "shared_proto_db" \
  "sentry" "logs" "Cache" "Code Cache" "GPUCache" "GPUPersistentCache" "GrShaderCache" "ShaderCache" \
  "DawnGraphiteCache" "DawnWebGPUCache" \
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

# temp claude directories (cache-break-state-*.json and per-session scratch state)
for base in "${TMPDIR%/}/claude" "/tmp/claude"; do
  if [ -d "$base" ]; then
    add_target "$base"
  fi
done

# ---- kept (chats & project memory) -----------------------------------------

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
echo "Kept (local chats & project memory):"
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
echo "Login and device IDs are removed. Local chat transcripts and project memory stay on disk."

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

# ---- edit claude_desktop_config.json (strip device & account fields) -------

CFG="$APPSUP/claude_desktop_config.json"
if [ -f "$CFG" ] && [ -n "$PY" ]; then
  echo "Editing claude_desktop_config.json"
  "$PY" - "$CFG" <<'EOF' 2>/dev/null || true
import json, re, sys
p = sys.argv[1]
uuid_re = re.compile(r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")
try:
    with open(p, encoding="utf-8-sig") as f:
        cfg = json.load(f)
    prefs = cfg.get("preferences")
    if isinstance(prefs, dict):
        for k in list(prefs.keys()):
            if k == "remoteToolsDeviceName" or k.endswith("ByAccount") or uuid_re.search(k):
                prefs.pop(k, None)
        ep = prefs.get("epitaxyPrefs")
        if isinstance(ep, dict):
            for k in list(ep.keys()):
                if uuid_re.search(k) or k in ("dframe-code-sections", "epitaxy-serene-whistle-decided", "epitaxy-split-suggestion"):
                    ep.pop(k, None)
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
