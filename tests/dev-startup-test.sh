#!/bin/sh
#
# Copyright 2026 Bundesagentur für Arbeit
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
LOG_FILE="$TMP_DIR/startup.log"

cleanup() {
  if [ -n "${PROXY_PID:-}" ] && kill -0 "$PROXY_PID" 2>/dev/null; then
    kill "$PROXY_PID" 2>/dev/null || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

mkdir -p "$TMP_DIR/bin" "$ROOT_DIR/target/providers"

cat > "$TMP_DIR/bin/oid4vc-dev" <<'EOF'
#!/bin/sh
set -eu

echo "oid4vc-dev $*" >> "$DEV_STARTUP_TEST_LOG"

if [ "$1" != "proxy" ]; then
  exit 0
fi

for arg in "$@"; do
  if [ "$arg" = "--" ]; then
    echo "unexpected wrapped service command" >> "$DEV_STARTUP_TEST_LOG"
    exit 42
  fi
done

echo "$$" > "$DEV_STARTUP_TEST_PROXY_PID"
trap 'exit 0' INT TERM
while :; do
  sleep 1
done
EOF

cat > "$TMP_DIR/bin/docker" <<'EOF'
#!/bin/sh
set -eu

echo "docker $*" >> "$DEV_STARTUP_TEST_LOG"
if [ -f "$DEV_STARTUP_TEST_PROXY_PID" ]; then
  kill "$(cat "$DEV_STARTUP_TEST_PROXY_PID")" 2>/dev/null || true
fi
exit 0
EOF

chmod +x "$TMP_DIR/bin/oid4vc-dev" "$TMP_DIR/bin/docker"

DEV_STARTUP_TEST_LOG="$LOG_FILE"
DEV_STARTUP_TEST_PROXY_PID="$TMP_DIR/proxy.pid"
export DEV_STARTUP_TEST_LOG DEV_STARTUP_TEST_PROXY_PID

PATH="$TMP_DIR/bin:$PATH" \
  "$ROOT_DIR/scripts/dev.sh" --no-build --skip-realm --no-ngrok >/dev/null

if grep -q "unexpected wrapped service command" "$LOG_FILE"; then
  echo "Assertion failed: oid4vc-dev proxy should not wrap docker compose" >&2
  cat "$LOG_FILE" >&2
  exit 1
fi

if ! grep -q '^oid4vc-dev proxy --target http://localhost:8080 --port 9090$' "$LOG_FILE"; then
  echo "Assertion failed: oid4vc-dev proxy should start as a standalone process" >&2
  cat "$LOG_FILE" >&2
  exit 1
fi

if ! grep -q '^docker compose -f docker-compose.yml -f .*/docker-compose.proxy.yml up --force-recreate --renew-anon-volumes keycloak$' "$LOG_FILE"; then
  echo "Assertion failed: docker compose should run in the foreground" >&2
  cat "$LOG_FILE" >&2
  exit 1
fi

: > "$LOG_FILE"

PATH="$TMP_DIR/bin:$PATH" \
  "$ROOT_DIR/scripts/dev.sh" --local-wallet --no-build --skip-realm --no-ngrok >/dev/null

if ! grep -q '^oid4vc-dev wallet serve --pid --docker --port 8087 --base-url  --register$' "$LOG_FILE"; then
  echo "Assertion failed: local-wallet mode should leave port 8086 free for oid4vc-dev wallet scan and clear persisted status-list URLs" >&2
  cat "$LOG_FILE" >&2
  exit 1
fi

echo "dev startup tests passed"
