#!/bin/sh
# Traffic cap for Cloady free tier: stop Xray at 190 GB/month (decimal),
# leaving 10 GB margin for TLS overhead and Cloady counting delay.
# Counts all container network I/O (rx+tx, all non-lo interfaces).
# Monthly total is stored in /data/monthly_usage.json and resets on the 1st (UTC).
set -u
LIMIT_BYTES=190000000000
STATE_DIR=/data
STATE_FILE="$STATE_DIR/monthly_usage.json"
mkdir -p "$STATE_DIR"
# Generate real config from template using env vars, so UUID/WS path
# are NOT stored in the GitHub repo. Set in Cloady: XRAY_UUID, WS_PATH.
if [ -n "${XRAY_UUID:-}" ] && [ -n "${WS_PATH:-}" ] && [ -f /etc/xray/config.template.json ]; then
  sed -e "s|__UUID__|$XRAY_UUID|g" -e "s|__WS_PATH__|$WS_PATH|g" /etc/xray/config.template.json > /etc/xray/config.json
  echo "[limit] generated /etc/xray/config.json from template"
fi

get_bytes() {
  total=0
  for f in /sys/class/net/*/statistics/rx_bytes; do
    iface=$(echo "$f" | cut -d/ -f5)
    if [ "$iface" = "lo" ]; then continue; fi
    rx=$(cat "$f" 2>/dev/null || echo 0)
    tx=$(cat "/sys/class/net/$iface/statistics/tx_bytes" 2>/dev/null || echo 0)
    total=$((total + rx + tx))
  done
  echo "$total"
}

load_state() {
  CUR_MONTH=$(date -u +%Y-%m)
  TOTAL=0
  if [ -f "$STATE_FILE" ]; then
    SAVED_MONTH=$(sed -n 's/.*"month": *"\([^"]*\)".*/\1/p' "$STATE_FILE" 2>/dev/null || echo "")
    SAVED_TOTAL=$(sed -n 's/.*"total": *\([0-9]*\).*/\1/p' "$STATE_FILE" 2>/dev/null || echo 0)
    if [ "$SAVED_MONTH" = "$CUR_MONTH" ]; then
      TOTAL=${SAVED_TOTAL:-0}
    else
      TOTAL=0
    fi
  fi
  echo "$CUR_MONTH $TOTAL"
}

save_state() {
  echo "{\"month\": \"$1\", \"total\": $2}" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
}

while true; do
  set -- $(load_state)
  MONTH="$1"; TOTAL="$2"
  echo "[limit] month=$MONTH used=${TOTAL}B limit=${LIMIT_BYTES}B"
  if [ "$TOTAL" -ge "$LIMIT_BYTES" ]; then
    echo "[limit] monthly cap reached (${TOTAL}B >= ${LIMIT_BYTES}B), Xray stays stopped until next month"
    save_state "$MONTH" "$TOTAL"
    sleep 3600
    continue
  fi
  /usr/local/bin/xray run -c /etc/xray/config.json &
  XRAY_PID=$!
  PREV=$(get_bytes)
  while kill -0 "$XRAY_PID" 2>/dev/null; do
    sleep 60
    set -- $(load_state)
    MONTH="$1"; TOTAL="$2"
    CUR=$(get_bytes)
    if [ "$CUR" -ge "$PREV" ]; then
      DELTA=$((CUR - PREV))
    else
      DELTA=0
    fi
    PREV="$CUR"
    TOTAL=$((TOTAL + DELTA))
    save_state "$MONTH" "$TOTAL"
    echo "[limit] month=$MONTH used=${TOTAL}B (+${DELTA}B) limit=${LIMIT_BYTES}B"
    if [ "$TOTAL" -ge "$LIMIT_BYTES" ]; then
      echo "[limit] cap reached, stopping Xray"
      kill "$XRAY_PID" 2>/dev/null || true
      wait "$XRAY_PID" 2>/dev/null || true
      break
    fi
  done
  wait "$XRAY_PID" 2>/dev/null || true
  # If Xray exited on its own (crash), loop will restart it unless cap was hit.
  # Small delay to avoid tight restart loop.
  sleep 5
done
