#!/usr/bin/env bash
# Samples a running Pesty while you leave it alone: average CPU, peak and
# current memory, and every network socket it holds (there should be none).
#
#   scripts/dev/measure_idle.sh            # 5 minutes
#   scripts/dev/measure_idle.sh 60         # 1 minute
set -euo pipefail

DURATION="${1:-300}"
PID="$(pgrep -x Pesty | head -1 || true)"
if [ -z "$PID" ]; then
  echo "Pesty is not running" >&2
  exit 1
fi

echo "==> Pesty pid $PID: sampling every 5 s for $DURATION s; leave the Mac idle"
START_CPU="$(ps -o time= -p "$PID" | tr -d ' ')"
END=$((SECONDS + DURATION))
while [ "$SECONDS" -lt "$END" ]; do
  ps -o %cpu=,rss= -p "$PID"
  sleep 5
done | awk '{ cpu += $1; if ($2 > max) max = $2; last = $2; n++ }
  END { printf "samples=%d  avg_cpu=%.2f%%  peak_rss=%.1f MB  last_rss=%.1f MB\n", n, cpu / n, max / 1024, last / 1024 }'
echo "    cpu time: $START_CPU -> $(ps -o time= -p "$PID" | tr -d ' ')"

echo "==> Memory footprint"
footprint "$PID" 2>/dev/null | grep -iE '^\s*(Footprint|phys_footprint)' | head -3 || echo "    (footprint unavailable)"

echo "==> Network sockets held by Pesty (expect none)"
if lsof -nP -i -a -p "$PID" 2>/dev/null; then
  echo "!! Pesty has open network sockets (listed above)"
else
  echo "    none"
fi
