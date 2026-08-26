#!/usr/bin/env bash
#
# compaction-capture.sh — PreCompact hook.
#
# Compaction is the one moment you KNOW detail is about to be destroyed. That
# makes it the only time "is anything here worth keeping?" is a well-posed
# question — and unlike "per session", it is a boundary the assistant can
# actually observe, because the system announces it.
#
# WHAT THIS DOES NOT DO: decide. It saves nothing to the brain. Auto-compaction
# can fire while you are away or mid-task, and a hook that writes entries
# unsupervised rebuilds the exact failure the review gate exists to prevent —
# a pile nobody vetted. This only makes sure the OPPORTUNITY survives the
# compaction; a human still judges, one turn later.
#
# It records the pre-compaction transcript path, so the assistant can read back
# what it is about to forget, and nudges it to offer any durable lesson.
#
# Install (user settings.json):
#   "hooks": { "PreCompact": [ { "hooks": [ {
#       "type": "command",
#       "command": "$HOME/.claude/hooks/compaction-capture.sh",
#       "timeout": 5 } ] } ] }
#
# stdin: hook JSON (session_id, transcript_path, trigger: "manual"|"auto")
# stdout: hook JSON with additionalContext
set -uo pipefail

STATE_DIR="${MEMBRAIN_COMPACT_STATE:-$HOME/.claude/membrain}"
mkdir -p "$STATE_DIR" 2>/dev/null

payload="$(cat 2>/dev/null || true)"

# Parse without assuming jq is installed — this runs on other people's machines.
read -r transcript trigger session <<EOF
$(printf '%s' "$payload" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
print(d.get("transcript_path", ""), d.get("trigger", "auto"), d.get("session_id", ""))
' 2>/dev/null || echo "  auto ")
EOF

# Keep only the most recent marker; this is a pointer, not an archive. We never
# copy transcript CONTENT here — that would duplicate the whole conversation
# into a second file on disk, which is a privacy liability, not a feature.
{
  printf 'transcript=%s\n' "$transcript"
  printf 'trigger=%s\n'    "$trigger"
  printf 'session=%s\n'    "$session"
} > "$STATE_DIR/last-compaction" 2>/dev/null

# A manual /compact is a deliberate act by someone who is present and knows what
# they just did. An automatic one fires on volume, often mid-flow. Nudge harder
# on the manual case; stay quieter on the automatic one.
if [ "$trigger" = "manual" ]; then
  msg="Context is being compacted now. If this stretch of work taught something durable and non-obvious, offer it to the human before the detail is gone (membrain-remember: one line, save/edit/skip). If it taught nothing worth keeping, say nothing — that is the common case."
else
  msg="Context is being auto-compacted. Detail from this stretch is about to be lost. Only if the work clearly taught something durable, offer it once via membrain-remember. The human may be mid-task; do not interrupt for anything marginal."
fi

python3 -c '
import json, sys
print(json.dumps({
    "suppressOutput": True,
    "hookSpecificOutput": {
        "hookEventName": "PreCompact",
        "additionalContext": sys.argv[1],
    },
}))
' "$msg" 2>/dev/null || true

exit 0
