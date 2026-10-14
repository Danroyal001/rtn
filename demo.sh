#!/usr/bin/env bash
# RTN in one command: the Rust core with 50 demo subscribers and live simulated
# traffic, and the Dartvel app (self-service + console) served in front of it.
#
#   ./demo.sh               build what is missing, then run everything
#   ./demo.sh --core-only   just the core and its API (no Flutter needed)
#   ./demo.sh --rebuild     rebuild the core and the app first
#
# Ctrl+C stops both and saves the network to .demo/rtn-state.json, which the
# next run picks up again. Delete .demo/ to start from a fresh network.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$ROOT/.demo"
CORE_ADDR="${RTN_ADDR:-127.0.0.1:8700}"
APP_PORT="${RTN_APP_PORT:-8740}"
CORE_ONLY=0
REBUILD=0
for arg in "$@"; do
  case "$arg" in
    --core-only) CORE_ONLY=1 ;;
    --rebuild) REBUILD=1 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "demo.sh: unknown option $arg" >&2; exit 2 ;;
  esac
done

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
need() { command -v "$1" >/dev/null 2>&1 || { echo "demo.sh: $1 is not installed. $2" >&2; exit 1; }; }

mkdir -p "$STATE_DIR"
need cargo "Install Rust from https://rustup.rs"

# Secrets for this machine's demo, made once and kept in .demo/ (git-ignored).
if [[ ! -f "$STATE_DIR/secrets.env" ]]; then
  umask 077
  {
    echo "RTN_ADMIN_TOKEN=$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')"
    echo "RTN_CONSOLE_PASSWORD=rtn-$(head -c 4 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  } > "$STATE_DIR/secrets.env"
fi
set -a; source "$STATE_DIR/secrets.env"; set +a

RTN_BIN="$ROOT/core/target/release/rtn"
if [[ $REBUILD == 1 || ! -x "$RTN_BIN" ]]; then
  say "Building the Rust core"
  (cd "$ROOT/core" && cargo build --release -p rtn-cli)
fi

PIDS=()
cleanup() {
  say "Stopping"
  for pid in "${PIDS[@]}"; do kill "$pid" 2>/dev/null || true; done
  wait 2>/dev/null || true
}
trap cleanup EXIT INT TERM

say "Starting the core on http://$CORE_ADDR"
"$RTN_BIN" serve --addr "$CORE_ADDR" --state "$STATE_DIR/rtn-state.json" --seed 50 --simulate \
  > "$STATE_DIR/core.log" 2>&1 &
PIDS+=($!)
for _ in $(seq 1 50); do
  curl -fsS "http://$CORE_ADDR/health" >/dev/null 2>&1 && break
  sleep 0.2
done
curl -fsS "http://$CORE_ADDR/health" >/dev/null || { cat "$STATE_DIR/core.log"; exit 1; }
SUBSCRIBERS=$(curl -fsS "http://$CORE_ADDR/health" | sed -E 's/.*"subscribers":([0-9]+).*/\1/')
say "The core is up with $SUBSCRIBERS subscribers and the traffic simulator on"

if [[ $CORE_ONLY == 0 ]]; then
  need dartvel "Install Dartvel: dart pub global activate dartvel_cli"
  SERVER="$ROOT/app/build/server"
  if [[ $REBUILD == 1 || ! -x "$SERVER" ]]; then
    say "Building the Dartvel web-server app (the first build takes a few minutes)"
    (cd "$ROOT/app" && dartvel build web-server)
  fi
  say "Starting the app on http://127.0.0.1:$APP_PORT"
  (cd "$STATE_DIR" && RTN_CORE_URL="http://$CORE_ADDR" DARTVEL_PORT="$APP_PORT" "$SERVER") \
    > "$STATE_DIR/app.log" 2>&1 &
  PIDS+=($!)
fi

if [[ $CORE_ONLY == 1 ]]; then
  cat <<INFO

  The RTN core is running on http://$CORE_ADDR (admin token in .demo/secrets.env).

    export RTN_API=http://$CORE_ADDR \$(grep RTN_ADMIN_TOKEN .demo/secrets.env)
    ./core/target/release/rtn subscribers
    ./core/target/release/rtn ussd 2349990000001

  Ctrl+C stops it.
INFO
  wait
  exit 0
fi

cat <<INFO

  RTN is running.

  Self-service    http://127.0.0.1:$APP_PORT/            sign in as 0999 000 0001 (to 0005), PIN 1234
  USSD dial pad   http://127.0.0.1:$APP_PORT/ussd        try *123#, *312#, *303#
  Console         http://127.0.0.1:$APP_PORT/console     password: $RTN_CONSOLE_PASSWORD
  Core API        http://$CORE_ADDR                   admin token in .demo/secrets.env

  From another terminal:
    export RTN_API=http://$CORE_ADDR \$(grep RTN_ADMIN_TOKEN .demo/secrets.env)
    ./core/target/release/rtn subscribers
    ./core/target/release/rtn ussd 2349990000001

  Logs are in .demo/. Ctrl+C stops everything.
INFO
wait
