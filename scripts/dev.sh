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
TOOLS_DIR="${ROOT_DIR}/tools"
TOOLS_BINDIR="${ROOT_DIR}/target/bin"
OID4VC_DEV_MODULE="github.com/dominikschlosser/oid4vc-dev"

DEFAULT_SANDBOX_DIR="${SANDBOX_DIR:-${ROOT_DIR}/sandbox}"
DEFAULT_PEM_FILE="${DEFAULT_SANDBOX_DIR}/sandbox-ngrok-combined.pem"
DEFAULT_VERIFIER_INFO="${DEFAULT_SANDBOX_DIR}/sandbox-verifier-info.json"

usage() {
  cat <<'EOF'
Usage: scripts/dev.sh [options]

One-command local development for the wallet connector distribution.

Modes:
  (default)                Sandbox mode for real wallet testing via ngrok
  --local-wallet           Local oid4vc-dev wallet mode

Options:
  --pem <file>             Combined PEM file for sandbox mode
                           Default: sandbox/sandbox-ngrok-combined.pem
  --verifier-info <file>   Verifier attestation JSON for sandbox mode
                           Default: sandbox/sandbox-verifier-info.json
  --trust-list-url <url>   Override trust list URL
  --domain <name>          Custom ngrok domain
  --wallet-port <port>     oid4vc-dev wallet port (default: 8086)
  --no-build               Skip provider download
  --skip-realm             Skip realm generation
  --no-proxy               Disable oid4vc-dev proxy even if available
  --no-ngrok               Run Keycloak without ngrok
  --ngrok-only             Start only ngrok tunnel, no Keycloak
  -h, --help               Show this help

Environment variables:
  SANDBOX_DIR              Base directory for sandbox credentials

Examples:
  scripts/dev.sh --local-wallet
  scripts/dev.sh
  scripts/dev.sh --pem /tmp/verifier.pem --verifier-info /tmp/verifier-info.json
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

resolve_oid4vc_dev_bin() {
  if command -v oid4vc-dev >/dev/null 2>&1; then
    command -v oid4vc-dev
    return 0
  fi

  if [ -x "${TOOLS_BINDIR}/oid4vc-dev" ]; then
    printf '%s\n' "${TOOLS_BINDIR}/oid4vc-dev"
    return 0
  fi

  return 1
}

oid4vc_dev_version() {
  go -C "$TOOLS_DIR" list -m -f '{{.Version}}' "$OID4VC_DEV_MODULE"
}

install_oid4vc_dev() {
  require_cmd go

  if [ ! -f "${TOOLS_DIR}/go.mod" ]; then
    echo "Tool manifest not found: ${TOOLS_DIR}/go.mod" >&2
    exit 1
  fi

  version="$(oid4vc_dev_version)"
  mkdir -p "$TOOLS_BINDIR"
  echo "==> Installing oid4vc-dev ${version} into target/bin/..."
  GOBIN="$TOOLS_BINDIR" go -C "$TOOLS_DIR" install "${OID4VC_DEV_MODULE}@${version}"
}

PEM_FILE="$DEFAULT_PEM_FILE"
VERIFIER_INFO="$DEFAULT_VERIFIER_INFO"
TRUST_LIST_URL=""
NGROK_DOMAIN=""
DOMAIN_EXPLICIT=false
DO_BUILD=true
DO_REALM=true
DO_PROXY=true
DO_NGROK=true
NGROK_ONLY=false
LOCAL_WALLET=false
WALLET_PORT=8086

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --local-wallet) LOCAL_WALLET=true; shift ;;
    --wallet-port) WALLET_PORT="$2"; shift 2 ;;
    --pem) PEM_FILE="$2"; shift 2 ;;
    --verifier-info) VERIFIER_INFO="$2"; shift 2 ;;
    --trust-list-url) TRUST_LIST_URL="$2"; shift 2 ;;
    --domain) NGROK_DOMAIN="$2"; DOMAIN_EXPLICIT=true; shift 2 ;;
    --no-build) DO_BUILD=false; shift ;;
    --skip-realm) DO_REALM=false; shift ;;
    --no-proxy) DO_PROXY=false; shift ;;
    --no-ngrok) DO_NGROK=false; shift ;;
    --ngrok-only) NGROK_ONLY=true; shift ;;
    *) echo "Unexpected argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

OID4VC_DEV_BIN=""
if resolved_bin="$(resolve_oid4vc_dev_bin 2>/dev/null)"; then
  OID4VC_DEV_BIN="$resolved_bin"
fi

if [ "$LOCAL_WALLET" = "true" ]; then
  DO_NGROK=false
  if [ -z "$OID4VC_DEV_BIN" ]; then
    install_oid4vc_dev
    OID4VC_DEV_BIN="$(resolve_oid4vc_dev_bin)"
  fi
fi

if [ "$DO_BUILD" = "true" ]; then
  "$ROOT_DIR/scripts/prepare-providers.sh"
else
  if [ ! -d "$ROOT_DIR/target/providers" ]; then
    echo "target/providers/ not found. Run without --no-build or run scripts/prepare-providers.sh." >&2
    exit 1
  fi
  echo "==> Skipping provider download (--no-build)"
fi

if [ "$DO_REALM" = "true" ]; then
  echo "==> Generating local realm config..."
  if [ "$LOCAL_WALLET" = "true" ]; then
    if [ -n "$TRUST_LIST_URL" ]; then
      "$ROOT_DIR/scripts/setup-local-realm.sh" --local-wallet --wallet-port "$WALLET_PORT" --trust-list-url "$TRUST_LIST_URL"
    else
      "$ROOT_DIR/scripts/setup-local-realm.sh" --local-wallet --wallet-port "$WALLET_PORT"
    fi
  else
    if [ ! -f "$PEM_FILE" ]; then
      echo "PEM file not found: $PEM_FILE" >&2
      echo "Set --pem or SANDBOX_DIR to point to your sandbox credentials." >&2
      exit 1
    fi
    if [ ! -f "$VERIFIER_INFO" ]; then
      echo "Verifier info file not found: $VERIFIER_INFO" >&2
      echo "Set --verifier-info or SANDBOX_DIR to point to your sandbox credentials." >&2
      exit 1
    fi
    if [ -n "$TRUST_LIST_URL" ]; then
      "$ROOT_DIR/scripts/setup-local-realm.sh" --pem "$PEM_FILE" --verifier-info "$VERIFIER_INFO" --trust-list-url "$TRUST_LIST_URL"
    else
      "$ROOT_DIR/scripts/setup-local-realm.sh" --pem "$PEM_FILE" --verifier-info "$VERIFIER_INFO"
    fi
  fi
else
  echo "==> Skipping realm generation (--skip-realm)"
fi

if [ "$DO_NGROK" = "true" ] && [ "$DOMAIN_EXPLICIT" = "false" ] && [ -f "$PEM_FILE" ] && command -v openssl >/dev/null 2>&1; then
  SAN_DNS="$(openssl x509 -in "$PEM_FILE" -noout -ext subjectAltName 2>/dev/null | grep -o 'DNS:[^ ,]*' | head -n1 | cut -d: -f2 || true)"
  if [ -n "$SAN_DNS" ]; then
    NGROK_DOMAIN="$SAN_DNS"
    echo "==> Detected ngrok domain from certificate SAN: $NGROK_DOMAIN"
  fi
fi

PROXY_PORT=9090
KC_PORT=8080

if [ "$DO_PROXY" = "true" ] && [ -n "$OID4VC_DEV_BIN" ]; then
  echo "==> oid4vc-dev proxy will wrap Keycloak (port $PROXY_PORT -> $KC_PORT)"
  echo "    oid4vc-dev dashboard: http://localhost:9091"
  export KC_WRAPPER="$OID4VC_DEV_BIN proxy --target http://localhost:$KC_PORT --port $PROXY_PORT --"
  export NGROK_TARGET_PORT="$PROXY_PORT"
elif [ "$DO_PROXY" = "true" ]; then
  echo "==> oid4vc-dev not found, skipping proxy"
fi

WALLET_PID=""
if [ "$LOCAL_WALLET" = "true" ]; then
  echo "==> Starting oid4vc-dev wallet on port $WALLET_PORT..."
  "$OID4VC_DEV_BIN" wallet serve --pid --port "$WALLET_PORT" --register &
  WALLET_PID=$!
  sleep 1
  echo "    Wallet UI: http://localhost:$WALLET_PORT"
  echo "    Trust list: http://localhost:$WALLET_PORT/api/trustlist"
fi

PROXY_OVERRIDE=""
cleanup() {
  if [ -n "$WALLET_PID" ] && kill -0 "$WALLET_PID" 2>/dev/null; then
    echo "==> Stopping oid4vc-dev wallet..."
    kill "$WALLET_PID" 2>/dev/null || true
  fi
  if [ -n "$PROXY_OVERRIDE" ]; then
    rm -f "$PROXY_OVERRIDE" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

if [ "$DO_NGROK" = "false" ]; then
  echo "==> Starting Keycloak (localhost only)..."
  cd "$ROOT_DIR"
  EXTERNAL_PORT="${NGROK_TARGET_PORT:-$KC_PORT}"
  COMPOSE_FILES="-f docker-compose.yml"
  if [ -n "${KC_WRAPPER:-}" ]; then
    PROXY_OVERRIDE="$ROOT_DIR/docker-compose.proxy.yml"
    cat > "$PROXY_OVERRIDE" <<YAML
services:
  keycloak:
    environment:
      KC_HOSTNAME: "http://localhost:$EXTERNAL_PORT"
      KC_PROXY_HEADERS: xforwarded
YAML
    COMPOSE_FILES="$COMPOSE_FILES -f $PROXY_OVERRIDE"
  fi
  echo "    Keycloak: http://localhost:$EXTERNAL_PORT"
  echo "    Admin console: http://localhost:$EXTERNAL_PORT/admin"
  ${KC_WRAPPER:-} docker compose $COMPOSE_FILES up keycloak
else
  echo "==> Starting ngrok + Keycloak..."
  NGROK_ARGS=""
  if [ -n "$NGROK_DOMAIN" ]; then
    NGROK_ARGS="--domain $NGROK_DOMAIN"
  fi
  if [ "$NGROK_ONLY" = "true" ]; then
    NGROK_ARGS="$NGROK_ARGS --ngrok-only"
  fi
  "$ROOT_DIR/scripts/run-keycloak-ngrok.sh" $NGROK_ARGS
fi
