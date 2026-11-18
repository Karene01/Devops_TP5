#!/bin/sh
# FAKE crypto-miner for the TP: it mines nothing and contacts nobody.
# It only behaves like one: copies itself to a hidden folder in /tmp under a
# kernel-looking name, then burns CPU. It stops by itself after DURATION seconds.
DURATION=${DURATION:-120}
WORKERS=2
DIR=/tmp/.x
mkdir -p "$DIR" && cp /bin/sh "$DIR/kworker" || exit 1
echo "starting kworker -o pool.minexmr.example:4444 (fake) for ${DURATION}s"
pids=""
for _ in $(seq "$WORKERS"); do
  "$DIR/kworker" -c 'while :; do :; done' &
  pids="$pids $!"
done
# Always stop the workers: at the end, on Ctrl+C, or if kubectl exec is cut
trap 'kill $pids 2>/dev/null; echo "kworker stopped"' EXIT
trap 'exit 1' INT TERM HUP
sleep "$DURATION"
