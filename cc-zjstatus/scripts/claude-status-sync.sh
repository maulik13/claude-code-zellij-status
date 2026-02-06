#!/bin/bash
# Reads Claude session state and sends it via zellij pipe to zjstatus.
# State is pushed to the JSON file by hook events (claude-activity-hook.sh).
# zjstatus runs this periodically to keep pipe_status synced across all tabs.

STATE_DIR="/tmp/claude-zellij-status"
ZELLIJ_SESSION="${ZELLIJ_SESSION_NAME:-}"

[ -z "$ZELLIJ_SESSION" ] && exit 0

STATE_FILE="${STATE_DIR}/${ZELLIJ_SESSION}.json"
[ -f "$STATE_FILE" ] && [ -s "$STATE_FILE" ] || exit 0

# Color defaults (must match claude-activity-hook.sh)
C_PROJECT="cyan"
C_TIME="bright_black"

# Load user overrides
CONFIG_FILE="${HOME}/.config/cc-zjstatus/colors.ini"
if [ -f "$CONFIG_FILE" ]; then
  while IFS='=' read -r key value; do
    key="${key// /}"
    value="${value// /}"
    [[ -z "$key" || "$key" == \#* || "$key" == \;* ]] && continue
    case "$key" in
      project) C_PROJECT="$value" ;;
      time) C_TIME="$value" ;;
    esac
  done < "$CONFIG_FILE"
fi

# Build combined status string (same format as hook script)
SESSIONS=""
while IFS= read -r line; do
  [ -z "$line" ] && continue
  [ -n "$SESSIONS" ] && SESSIONS="${SESSIONS}  "
  SESSIONS="${SESSIONS}${line}"
done < <(jq -r --arg proj_color "$C_PROJECT" --arg time_color "$C_TIME" '
    to_entries | sort_by(.key)[] |
    "#[fg=\(.value.color)]\(.value.symbol) #[fg=\($proj_color)]\(.value.project) #[fg=\($time_color)]@\(.value.time)" +
    (if .value.context_pct then " #[fg=\(.value.ctx_color // "green")]\(.value.context_pct)%" else "" end)
' "$STATE_FILE" 2>/dev/null)

# Send via pipe in background to avoid deadlock (zjstatus waits for this
# script to finish, but zellij pipe waits for zjstatus to process the message)
if [ -n "$SESSIONS" ]; then
  (zellij pipe "zjstatus::pipe::pipe_status::${SESSIONS}" &>/dev/null &)
fi

# Output a space so zjstatus considers this command "active"
echo " "
