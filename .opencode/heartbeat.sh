#!/usr/bin/env bash
set -euo pipefail

# bilimbi heartbeat — adaptive loop that wakes opencode to check for work.
# Attaches to a running opencode server and injects periodic heartbeat messages
# without quitting the user's TUI session.
#
# Prerequisites:
#   Start opencode with a known port so the heartbeat can attach:
#     opencode --port 4096
#   Or use serve+attach:
#     Terminal 1: opencode serve --port 4096
#     Terminal 2: opencode attach http://localhost:4096 --continue
#
# Usage:
#   .opencode/heartbeat.sh --server http://localhost:4096
#   .opencode/heartbeat.sh --server http://localhost:4096 --once
#   .opencode/heartbeat.sh --server http://localhost:4096 --interval 600

REPO="BelimbingApp/bilimbi"
STATE_DIR=".opencode/heartbeat"
STATE_FILE="${STATE_DIR}/state.json"
SERVER="${HEARTBEAT_SERVER:-http://localhost:4096}"
BASE_INTERVAL="${HEARTBEAT_INTERVAL:-600}"
MAX_INTERVAL=1800
COOLDOWN_MULTIPLIER=1.5

mkdir -p "$STATE_DIR"

if [[ ! -f "$STATE_FILE" ]]; then
  cat > "$STATE_FILE" <<'JSON'
{"last_tick":null,"idle_count":0,"halted":false,"current_interval":600}
JSON
fi

write_state() {
  local key="$1" value="$2"
  local tmp
  tmp=$(mktemp)
  jq ".${key} = ${value}" "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

ONCE=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --once)      ONCE=true; shift ;;
    --server)    SERVER="$2"; shift 2 ;;
    --interval)  BASE_INTERVAL="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

INTERVAL="$BASE_INTERVAL"
[[ -f "$STATE_FILE" ]] && INTERVAL=$(jq -r '.current_interval // empty' "$STATE_FILE")
INTERVAL="${INTERVAL:-$BASE_INTERVAL}"

# Verify server is reachable
check_server() {
  if command -v curl &>/dev/null; then
    curl -sf -o /dev/null "${SERVER}/global/health" 2>/dev/null && return 0
  fi
  return 1
}

tick() {
  echo "[$(date --iso-8601=seconds)] heartbeat tick — interval=${INTERVAL}s server=$SERVER"

  if ! check_server; then
    echo "[$(date --iso-8601=seconds)] WARNING: server $SERVER not reachable — skipping tick"
    return 1
  fi

  local result
  set +e
  opencode run --attach "$SERVER" --continue --command heartbeat 2>&1
  result=$?
  set -e
  echo "[$(date --iso-8601=seconds)] heartbeat finished — exit=$result"
}

run_once() {
  local halted
  halted=$(jq -r '.halted' "$STATE_FILE")
  if [[ "$halted" == "true" ]]; then
    echo "[$(date --iso-8601=seconds)] halted — check #208 for halt directive"
    return
  fi
  tick
}

if $ONCE; then
  run_once
  exit 0
fi

echo "=== bilimbi heartbeat started ==="
echo "Server:   ${SERVER}"
echo "Interval: ${BASE_INTERVAL}s base / ${MAX_INTERVAL}s max / ${COOLDOWN_MULTIPLIER}x cooldown"
echo "State:    ${STATE_FILE}"
echo "Stop:     echo '{\"halted\":true}' | jq . > ${STATE_FILE}  or Ctrl-C"
echo ""

while true; do
  run_once

  local_idle=$(jq -r '.idle_count' "$STATE_FILE")
  local_halted=$(jq -r '.halted' "$STATE_FILE")

  if [[ "$local_halted" == "true" ]]; then
    echo "[$(date --iso-8601=seconds)] halt flag set — exiting loop."
    break
  fi

  if [[ "$local_idle" -ge 2 ]]; then
    INTERVAL=$(echo "$INTERVAL * $COOLDOWN_MULTIPLIER" | bc | cut -d. -f1)
    if [[ "$INTERVAL" -gt "$MAX_INTERVAL" ]]; then
      INTERVAL="$MAX_INTERVAL"
    fi
    write_state current_interval "$INTERVAL"
  else
    INTERVAL="$BASE_INTERVAL"
    write_state current_interval "$INTERVAL"
  fi

  echo "[$(date --iso-8601=seconds)] sleeping ${INTERVAL}s..."
  sleep "$INTERVAL"
done
