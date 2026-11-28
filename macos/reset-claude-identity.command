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

set -u

APPLY=0
for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
  esac
done

HOME_DIR="${HOME:-}"
HOME_DIR="${HOME_DIR%/}"
if [ -z "$HOME_DIR" ] || [ ! -d "$HOME_DIR" ]; then
  echo "HOME is not set to a valid directory." >&2
  exit 1
fi

TMP_ROOT="${TMPDIR:-/tmp}"
TMP_ROOT="${TMP_ROOT%/}"
[ -n "$TMP_ROOT" ] || TMP_ROOT="/tmp"

CLAUDE_HOME="$HOME_DIR/.claude"
APPSUP="$HOME_DIR/Library/Application Support/Claude"
APPSUP_3P="$HOME_DIR/Library/Application Support/Claude-3p"

# ---- helpers ---------------------------------------------------------------

have() { command -v "$1" >/dev/null 2>&1; }

# Prefer built-in macOS JXA (osascript -l JavaScript) so JSON parsing/editing
# works on every Mac without triggering the Xcode Command Line Tools popup
# that /usr/bin/python3 shows on a fresh system.
HAS_OSASCRIPT=0
if have osascript; then HAS_OSASCRIPT=1; fi

PY=""
if [ "$HAS_OSASCRIPT" -eq 0 ]; then
  if ! have xcode-select || xcode-select -p >/dev/null 2>&1; then
    if have python3; then PY="python3"; elif have python; then PY="python"; fi
  fi
fi

json_get() {
  # json_get <file> <dot.separated.key>
  [ -f "$1" ] || { printf ''; return; }
  if [ "$HAS_OSASCRIPT" -eq 1 ]; then
    osascript -l JavaScript - "$1" "$2" <<'EOF' 2>/dev/null || true
ObjC.import('Foundation');
function run(argv) {
  try {
    var data = $.NSData.dataWithContentsOfFile(argv[0]);
    if (!data || data.length === 0) return '';
    var ns = $.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding);
    if (!ns) return '';
    var text = ObjC.unwrap(ns);
    if (text.length > 0 && text.charCodeAt(0) === 0xFEFF) text = text.slice(1);
    var cur = JSON.parse(text);
    var parts = argv[1].split('.');
    for (var i = 0; i < parts.length; i++) {
      if (cur === null || typeof cur !== 'object') return '';
      cur = cur[parts[i]];
    }
    if (cur === undefined || cur === null || typeof cur === 'object') return '';
    return String(cur);
  } catch (e) {
    return '';
  }
}
EOF
  elif [ -n "$PY" ]; then
    "$PY" - "$1" "$2" <<'EOF' 2>/dev/null || true
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8-sig") as f:
        cur = json.load(f)
    for part in sys.argv[2].split("."):
        if not isinstance(cur, dict):
            cur = None
            break
        cur = cur.get(part)
    print("" if cur is None or isinstance(cur, (dict, list)) else str(cur))
except Exception:
    print("")
EOF
  else
    local leaf="${2##*.}"
    sed -n "s/.*\"$leaf\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$1" | head -n 1
  fi
}

json_key_count() {
  # json_key_count <file>
  [ -f "$1" ] || { printf ''; return; }
  if [ "$HAS_OSASCRIPT" -eq 1 ]; then
    osascript -l JavaScript - "$1" <<'EOF' 2>/dev/null || true
ObjC.import('Foundation');
function run(argv) {
  try {
    var data = $.NSData.dataWithContentsOfFile(argv[0]);
    if (!data || data.length === 0) return '';
    var ns = $.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding);
    if (!ns) return '';
    var text = ObjC.unwrap(ns);
    if (text.length > 0 && text.charCodeAt(0) === 0xFEFF) text = text.slice(1);
    var obj = JSON.parse(text);
    if (!obj || typeof obj !== 'object' || Array.isArray(obj)) return '';
    return String(Object.keys(obj).length);
  } catch (e) {
    return '';
  }
}
EOF
  elif [ -n "$PY" ]; then
    "$PY" - "$1" <<'EOF' 2>/dev/null || true
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8-sig") as f:
        obj = json.load(f)
    print(str(len(obj)) if isinstance(obj, dict) else "")
except Exception:
    print("")
EOF
  else
    printf ''
  fi
}

clear_desktop_identity_fields() {
  local cfg_path="$1"
  [ -f "$cfg_path" ] || return 0
  if [ "$HAS_OSASCRIPT" -eq 1 ]; then
    osascript -l JavaScript - "$cfg_path" <<'EOF' >/dev/null 2>&1
ObjC.import('Foundation');
function run(argv) {
  var p = argv[0];
  var uuidRe = /[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/;
  var data = $.NSData.dataWithContentsOfFile(p);
  if (!data || data.length === 0) throw new Error('unreadable');
  var ns = $.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding);
  if (!ns) throw new Error('invalid utf8');
  var text = ObjC.unwrap(ns);
  if (text.length > 0 && text.charCodeAt(0) === 0xFEFF) text = text.slice(1);
  var cfg = JSON.parse(text);
  if (cfg && typeof cfg === 'object' && cfg.preferences && typeof cfg.preferences === 'object' && !Array.isArray(cfg.preferences)) {
    var prefs = cfg.preferences;
    Object.keys(prefs).forEach(function(k) {
      if (k === 'remoteToolsDeviceName' || /ByAccount$/.test(k) || uuidRe.test(k)) {
        delete prefs[k];
      }
    });
    var ep = prefs.epitaxyPrefs;
    if (ep && typeof ep === 'object' && !Array.isArray(ep)) {
      var drop = {'dframe-code-sections': 1, 'epitaxy-serene-whistle-decided': 1, 'epitaxy-split-suggestion': 1};
      Object.keys(ep).forEach(function(k) {
        if (uuidRe.test(k) || drop[k]) {
          delete ep[k];
        }
      });
    }
  }
  var out = JSON.stringify(cfg, null, 2) + '\n';
  var outNs = $(out);
  if (!outNs.writeToFileAtomicallyEncodingError(p, true, $.NSUTF8StringEncoding, null)) {
    throw new Error('write failed');
  }
  return 'ok';
}
EOF
    return $?
  elif [ -n "$PY" ]; then
    "$PY" - "$cfg_path" <<'EOF' >/dev/null 2>&1
import json, re, sys
p = sys.argv[1]
uuid_re = re.compile(r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")
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
    f.write("\n")
EOF
    return $?
  elif have node; then
    node - "$cfg_path" <<'EOF' >/dev/null 2>&1
const fs = require('fs');
const p = process.argv[2];
const uuidRe = /[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/;
let text = fs.readFileSync(p, 'utf8');
if (text.charCodeAt(0) === 0xFEFF) text = text.slice(1);
const cfg = JSON.parse(text);
if (cfg && typeof cfg === 'object' && cfg.preferences && typeof cfg.preferences === 'object' && !Array.isArray(cfg.preferences)) {
  const prefs = cfg.preferences;
  for (const k of Object.keys(prefs)) {
    if (k === 'remoteToolsDeviceName' || k.endsWith('ByAccount') || uuidRe.test(k)) {
      delete prefs[k];
    }
  }
  const ep = prefs.epitaxyPrefs;
  if (ep && typeof ep === 'object' && !Array.isArray(ep)) {
    const drop = new Set(['dframe-code-sections', 'epitaxy-serene-whistle-decided', 'epitaxy-split-suggestion']);
    for (const k of Object.keys(ep)) {
      if (uuidRe.test(k) || drop.has(k)) {
        delete ep[k];
      }
    }
  }
}
fs.writeFileSync(p, JSON.stringify(cfg, null, 2) + '\n', 'utf8');
EOF
    return $?
  fi
  echo "Could not edit $cfg_path (no osascript, python, or node available)"
  return 1
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
    local acct_uuid
    acct_uuid="$(json_get "$cli" oauthAccount.accountUuid)"
    if [ -n "${acct_uuid//[$'\t\r\n ']/}" ]; then
      printf '  CLI account   : %s\n' "$(prefix "$acct_uuid")"
    else
      printf '  CLI account   : absent\n'
    fi
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
  if [ -f "$APPSUP/ant-device-registry.json" ]; then
    local reg_count
    reg_count="$(json_key_count "$APPSUP/ant-device-registry.json")"
    if [ -n "$reg_count" ]; then
      printf '  device registry entries: %s\n' "$reg_count"
    else
      printf '  device registry: present\n'
    fi
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
    "$TMP_ROOT"/*|/tmp/*) : ;;
    *) return 0 ;;
  esac
  local existing
  if [ "${#TARGETS[@]}" -gt 0 ]; then
    for existing in "${TARGETS[@]}"; do
      [ "$existing" = "$p" ] && return 0
    done
  fi
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
for base in "$TMP_ROOT/claude" "/tmp/claude"; do
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
if [ "${#TARGETS[@]}" -gt 0 ]; then
  for t in "${TARGETS[@]}"; do
    echo "Removing $t"
    remove_target "$t" || FAILED+=("$t")
  done
fi

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
if [ -f "$CFG" ]; then
  echo "Editing claude_desktop_config.json"
  clear_desktop_identity_fields "$CFG" || FAILED+=("$CFG")
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
