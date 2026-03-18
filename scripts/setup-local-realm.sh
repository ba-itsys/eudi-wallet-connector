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
BASE_REALM="${ROOT_DIR}/config/realm-wallet-connector-base.json"
REALM_OUT="${ROOT_DIR}/generated/realm-wallet-connector-local.json"
DEFAULT_SANDBOX_TRUST_LIST_URL="https://bmi.usercontent.opencode.de/eudi-wallet/test-trust-lists/pid-provider.jwt"

usage() {
  cat <<'EOF'
Usage:
  scripts/setup-local-realm.sh --local-wallet [--wallet-port <port>] [--trust-list-url <url>] [--output <file>]
  scripts/setup-local-realm.sh --pem <file> --verifier-info <file> [--trust-list-url <url>] [--output <file>]

Modes:
  --local-wallet           Configure the connector for the local oid4vc-dev wallet
  --pem/--verifier-info    Configure the connector for a real wallet sandbox

Options:
  --wallet-port <port>     oid4vc-dev wallet port (default: 8086)
  --trust-list-url <url>   Override trust list URL
  --output <file>          Output realm file
  -h, --help               Show this help
EOF
}

LOCAL_WALLET=false
WALLET_PORT=8086
PEM_FILE=""
VERIFIER_INFO_FILE=""
TRUST_LIST_URL=""
OUTPUT_FILE="$REALM_OUT"

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --local-wallet) LOCAL_WALLET=true; shift ;;
    --wallet-port) WALLET_PORT="$2"; shift 2 ;;
    --pem) PEM_FILE="$2"; shift 2 ;;
    --verifier-info) VERIFIER_INFO_FILE="$2"; shift 2 ;;
    --trust-list-url) TRUST_LIST_URL="$2"; shift 2 ;;
    --output) OUTPUT_FILE="$2"; shift 2 ;;
    *) echo "Unexpected argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [ ! -f "$BASE_REALM" ]; then
  echo "Base realm template not found: $BASE_REALM" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_FILE")"

if [ "$LOCAL_WALLET" = "true" ]; then
  TRUST_LIST_URL="${TRUST_LIST_URL:-http://host.docker.internal:${WALLET_PORT}/api/trustlist}"

  jq \
    --arg trustListUrl "$TRUST_LIST_URL" \
    '
      .identityProviders[0].config.enforceHaip = "false"
      | .identityProviders[0].config.responseMode = "direct_post"
      | .identityProviders[0].config.clientIdScheme = "plain"
      | .identityProviders[0].config.trustedAuthoritiesMode = "none"
      | .identityProviders[0].config.trustListUrl = $trustListUrl
      | del(.identityProviders[0].config.x509CertificatePem)
      | del(.identityProviders[0].config.verifierInfo)
    ' \
    "$BASE_REALM" > "$OUTPUT_FILE"
else
  if [ -z "$PEM_FILE" ] || [ -z "$VERIFIER_INFO_FILE" ]; then
    echo "Sandbox mode requires --pem and --verifier-info." >&2
    usage >&2
    exit 2
  fi
  if [ ! -f "$PEM_FILE" ]; then
    echo "PEM file not found: $PEM_FILE" >&2
    exit 1
  fi
  if [ ! -f "$VERIFIER_INFO_FILE" ]; then
    echo "Verifier info file not found: $VERIFIER_INFO_FILE" >&2
    exit 1
  fi

  TRUST_LIST_URL="${TRUST_LIST_URL:-$DEFAULT_SANDBOX_TRUST_LIST_URL}"

  jq \
    --arg trustListUrl "$TRUST_LIST_URL" \
    --rawfile pem "$PEM_FILE" \
    --rawfile verifierInfo "$VERIFIER_INFO_FILE" \
    '
      .identityProviders[0].config.enforceHaip = "true"
      | .identityProviders[0].config.responseMode = "direct_post.jwt"
      | .identityProviders[0].config.clientIdScheme = "x509_hash"
      | .identityProviders[0].config.trustedAuthoritiesMode = "none"
      | .identityProviders[0].config.trustListUrl = $trustListUrl
      | .identityProviders[0].config.x509CertificatePem = $pem
      | .identityProviders[0].config.verifierInfo = $verifierInfo
    ' \
    "$BASE_REALM" > "$OUTPUT_FILE"
fi

echo "Generated: $OUTPUT_FILE"
