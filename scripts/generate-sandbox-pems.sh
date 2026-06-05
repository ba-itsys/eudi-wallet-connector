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
SANDBOX_DIR="${ROOT_DIR}/sandbox"
CERT_FILE=""
NGROK_CERT_FILE=""
KEY_FILE=""
NGROK_DOMAIN="wallet-test.ngrok.dev"

usage() {
  cat <<'EOF'
Usage: scripts/generate-sandbox-pems.sh [options]

Generates combined SPRIND sandbox PEM files from the sandbox certificate and
relying-party private key.

Options:
  --sandbox-dir <dir>  Sandbox credential directory (default: sandbox)
  --cert <file>        Certificate PEM file (default: <sandbox-dir>/sandbox.crt)
  --ngrok-cert <file>  Ngrok certificate PEM file
                       Default: <sandbox-dir>/sandbox-ngrok.crt when present,
                       otherwise <sandbox-dir>/sandbox.crt
  --key <file>         Private key PEM file (default: <sandbox-dir>/rp.key)
  --ngrok-domain <dns> Required ngrok certificate DNS SAN
                       Default: wallet-test.ngrok.dev
  -h, --help           Show this help

Outputs:
  <sandbox-dir>/sandbox-combined.pem
  <sandbox-dir>/sandbox-ngrok-combined.pem
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --sandbox-dir) SANDBOX_DIR="$2"; shift 2 ;;
    --cert) CERT_FILE="$2"; shift 2 ;;
    --ngrok-cert) NGROK_CERT_FILE="$2"; shift 2 ;;
    --key) KEY_FILE="$2"; shift 2 ;;
    --ngrok-domain) NGROK_DOMAIN="$2"; shift 2 ;;
    *) echo "Unexpected argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

CERT_FILE="${CERT_FILE:-${SANDBOX_DIR}/sandbox.crt}"
if [ -z "$NGROK_CERT_FILE" ]; then
  if [ -f "${SANDBOX_DIR}/sandbox-ngrok.crt" ]; then
    NGROK_CERT_FILE="${SANDBOX_DIR}/sandbox-ngrok.crt"
  else
    NGROK_CERT_FILE="$CERT_FILE"
  fi
fi
KEY_FILE="${KEY_FILE:-${SANDBOX_DIR}/rp.key}"
SANDBOX_COMBINED="${SANDBOX_DIR}/sandbox-combined.pem"
SANDBOX_NGROK_COMBINED="${SANDBOX_DIR}/sandbox-ngrok-combined.pem"

require_cmd openssl
require_cmd cmp

if [ ! -d "$SANDBOX_DIR" ]; then
  echo "Sandbox directory not found: $SANDBOX_DIR" >&2
  exit 1
fi
if [ ! -f "$CERT_FILE" ]; then
  echo "Certificate file not found: $CERT_FILE" >&2
  exit 1
fi
if [ ! -f "$NGROK_CERT_FILE" ]; then
  echo "Ngrok certificate file not found: $NGROK_CERT_FILE" >&2
  exit 1
fi
if [ ! -f "$KEY_FILE" ]; then
  echo "Private key file not found: $KEY_FILE" >&2
  exit 1
fi

cert_pub="$(mktemp "${TMPDIR:-/tmp}/sandbox-cert-pub.XXXXXX")"
ngrok_cert_pub="$(mktemp "${TMPDIR:-/tmp}/sandbox-ngrok-cert-pub.XXXXXX")"
key_pub="$(mktemp "${TMPDIR:-/tmp}/sandbox-key-pub.XXXXXX")"
combined_tmp="$(mktemp "${TMPDIR:-/tmp}/sandbox-combined.XXXXXX")"
ngrok_tmp="$(mktemp "${TMPDIR:-/tmp}/sandbox-ngrok-combined.XXXXXX")"
cleanup() {
  rm -f "$cert_pub" "$ngrok_cert_pub" "$key_pub" "$combined_tmp" "$ngrok_tmp"
}
trap cleanup EXIT INT TERM

openssl x509 -in "$CERT_FILE" -noout >/dev/null
openssl x509 -in "$NGROK_CERT_FILE" -noout >/dev/null
openssl pkey -in "$KEY_FILE" -noout >/dev/null
openssl x509 -in "$CERT_FILE" -pubkey -noout | openssl pkey -pubin -pubout > "$cert_pub"
openssl x509 -in "$NGROK_CERT_FILE" -pubkey -noout | openssl pkey -pubin -pubout > "$ngrok_cert_pub"
openssl pkey -in "$KEY_FILE" -pubout > "$key_pub"

if ! cmp -s "$cert_pub" "$key_pub"; then
  echo "Certificate and private key do not match: $CERT_FILE $KEY_FILE" >&2
  exit 1
fi
if ! cmp -s "$ngrok_cert_pub" "$key_pub"; then
  echo "Ngrok certificate and private key do not match: $NGROK_CERT_FILE $KEY_FILE" >&2
  exit 1
fi
if ! openssl x509 -in "$NGROK_CERT_FILE" -noout -ext subjectAltName \
    | grep -F "DNS:${NGROK_DOMAIN}" >/dev/null 2>&1; then
  echo "Ngrok certificate does not contain DNS SAN ${NGROK_DOMAIN}: $NGROK_CERT_FILE" >&2
  exit 1
fi

{
  cat "$CERT_FILE"
  printf '\n'
  cat "$KEY_FILE"
} > "$combined_tmp"

{
  cat "$NGROK_CERT_FILE"
  printf '\n'
  cat "$KEY_FILE"
} > "$ngrok_tmp"

mv "$combined_tmp" "$SANDBOX_COMBINED"
mv "$ngrok_tmp" "$SANDBOX_NGROK_COMBINED"

echo "Generated: $SANDBOX_COMBINED"
echo "Generated: $SANDBOX_NGROK_COMBINED"
