#!/usr/bin/env bash
# RTN in one command: MyRTN and the operator console, with the Rust core loaded
# into the app's server, 50 demo subscribers and live simulated traffic.
#
#   ./demo.sh               build what is missing, then run it
#   ./demo.sh --http        run the core as its own process (rtn serve) instead
#   ./demo.sh --core-only   just the core and its HTTP API (no Flutter needed)
#   ./demo.sh --rebuild     rebuild the core and the app first
#
# The network is kept in .demo/network: a journal of every change, written
# before it is answered, and a snapshot. Ctrl+C stops everything; the next run
# carries on from where it was. Delete .demo/ to start a fresh network.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO="$ROOT/.demo"
CORE_ADDR="${RTN_ADDR:-127.0.0.1:8700}"
APP_PORT="${RTN_APP_PORT:-8740}"
MODE=inprocess
REBUILD=0
for arg in "$@"; do
  case "$arg" in
    --http) MODE=http ;;
    --core-only) MODE=core ;;
    --rebuild) REBUILD=1 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "demo.sh: unknown option $arg" >&2; exit 2 ;;
  esac
done

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
need() { command -v "$1" >/dev/null 2>&1 || { echo "demo.sh: $1 is not installed. $2" >&2; exit 1; }; }
wait_for() { # url, log
  for _ in $(seq 1 100); do curl -fsS "$1" >/dev/null 2>&1 && return 0; sleep 0.2; done
  echo "demo.sh: nothing answered at $1. The log says:" >&2; tail -20 "$2" >&2; exit 1
}

mkdir -p "$DEMO"
need cargo "Install Rust from https://rustup.rs"
need curl "Install curl"

# This machine's demo secrets, made once and kept in .demo/ (git-ignored).
if [[ ! -f "$DEMO/secrets.env" ]]; then
  umask 077
  {
    echo "RTN_ADMIN_TOKEN=$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')"
    echo "RTN_CONSOLE_PASSWORD=rtn-$(head -c 4 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  } > "$DEMO/secrets.env"
fi
set -a; source "$DEMO/secrets.env"; set +a

case "$(uname -s)" in
  Darwin) LIB="$ROOT/core/target/release/librtn_ffi.dylib" ;;
  *) LIB="$ROOT/core/target/release/librtn_ffi.so" ;;
esac
RTN_BIN="$ROOT/core/target/release/rtn"
if [[ $REBUILD == 1 || ! -x "$RTN_BIN" || ! -f "$LIB" ]]; then
  say "Building the Rust core"
  (cd "$ROOT/core" && cargo build --release -p rtn-cli -p rtn-ffi)
fi

PIDS=()
cleanup() {
  say "Stopping"
  for pid in "${PIDS[@]}"; do kill "$pid" 2>/dev/null || true; done
  wait 2>/dev/null || true
}
trap cleanup EXIT INT TERM

if [[ $MODE != inprocess ]]; then
  say "Starting the core on http://$CORE_ADDR"
  "$RTN_BIN" serve --addr "$CORE_ADDR" --data "$DEMO/network" --seed 50 --simulate > "$DEMO/core.log" 2>&1 &
  PIDS+=($!)
  wait_for "http://$CORE_ADDR/health" "$DEMO/core.log"
  SUBSCRIBERS=$(curl -fsS "http://$CORE_ADDR/health" | sed -E 's/.*"subscribers":([0-9]+).*/\1/')
  say "The core is up with $SUBSCRIBERS subscribers and the traffic simulator on"
fi

if [[ $MODE == core ]]; then
  cat <<INFO

  The RTN core is running on http://$CORE_ADDR.

    export RTN_API=http://$CORE_ADDR \$(grep RTN_ADMIN_TOKEN .demo/secrets.env)
    ./core/target/release/rtn subscribers
    ./core/target/release/rtn ussd 2349990000001
    ./core/target/release/rtn vouchers --count 3 --naira 500
    ./core/target/release/rtn inbox 2349990000001

  Ctrl+C stops it.
INFO
  wait
  exit 0
fi

need dartvel "Install Dartvel: dart pub global activate dartvel_cli"
SERVER="$ROOT/app/build/server"
if [[ $REBUILD == 1 || ! -x "$SERVER" ]]; then
  say "Building the MyRTN web-server (the first build takes a few minutes)"
  # The build opens each public page in a headless Chrome to write its HTML;
  # set DARTVEL_CHROME if yours is not where Dartvel looks.
  (cd "$ROOT/app" && dartvel build web-server)
fi

say "Starting MyRTN on http://127.0.0.1:$APP_PORT"
export DARTVEL_PORT="$APP_PORT" RTN_DEMO=1
if [[ $MODE == inprocess ]]; then
  export RTN_CORE_LIB="$LIB" RTN_DATA="$DEMO/network" RTN_SEED=50 RTN_SIMULATE=1
else
  export RTN_CORE_URL="http://$CORE_ADDR"
fi
(cd "$DEMO" && "$SERVER") > "$DEMO/app.log" 2>&1 &
PIDS+=($!)
wait_for "http://127.0.0.1:$APP_PORT/api/status" "$DEMO/app.log"
STATUS=$(curl -fsS "http://127.0.0.1:$APP_PORT/api/status")
case "$STATUS" in
  *'"code":""'*) say "The network is up: $(echo "$STATUS" | sed -E 's/.*"value":\{"message":"([^"]*)".*/\1/')" ;;
  *) echo "demo.sh: the app cannot read the network: $STATUS" >&2; exit 1 ;;
esac

CORE_LINE="in this process (librtn_ffi), kept in .demo/network"
[[ $MODE == http ]] && CORE_LINE="rtn serve on http://$CORE_ADDR, kept in .demo/network"
cat <<INFO

  RTN is running. The core is $CORE_LINE.

  MyRTN      http://127.0.0.1:$APP_PORT/        sign in as any of 0999 000 0001 to 0999 000 0050.
                                                 The code goes out by SMS; this demo also shows it
                                                 on the page. Transfer PIN for 0001 to 0005: 1234
  Console    http://127.0.0.1:$APP_PORT/operator  password: $RTN_CONSOLE_PASSWORD
  Cards      4242 4242 4242 4242 is approved, 4000 0000 0000 0002 is declined (MockPay, no real money)

  Logs are in .demo/. Ctrl+C stops everything; the network is kept for the next run.
INFO
wait
