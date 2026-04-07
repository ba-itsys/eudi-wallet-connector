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

BASE_URL="${BASE_URL:-http://localhost:8080}"
REALM="${REALM:-wallet-connector}"
CLIENT_ID="${CLIENT_ID:-wallet-rp}"
REDIRECT_URI="${REDIRECT_URI:-http://127.0.0.1:18080/callback}"
SCOPE="${SCOPE:-openid wallet-pid}"
IDP_HINT="${IDP_HINT:-}"
AUTO_OPEN=true

usage() {
  cat <<'EOF'
Usage: scripts/test-oidc-flow.sh [options]

Runs an interactive OAuth/OIDC authorization-code flow against the running wallet connector
and prints the decoded id_token payload.

Options:
  --base-url <url>        Keycloak base URL (default: http://localhost:8080)
  --realm <name>          Realm name (default: wallet-connector)
  --client-id <id>        Client ID (default: wallet-rp)
  --redirect-uri <uri>    Redirect URI (default: http://127.0.0.1:18080/callback)
  --scope <scope>         OAuth scope (default: "openid wallet-pid")
  --idp-hint <alias>      IdP hint override
  --no-open               Do not auto-open the browser
  -h, --help              Show this help
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

urlencode() {
  jq -nr --arg value "$1" '$value|@uri'
}

urldecode() {
  printf '%b' "$(printf '%s' "$1" | sed 's/+/ /g; s/%/\\x/g')"
}

random_urlsafe() {
  openssl rand -base64 48 | tr '+/' '-_' | tr -d '=\n'
}

pkce_challenge() {
  printf '%s' "$1" \
    | openssl dgst -binary -sha256 \
    | openssl base64 -A \
    | tr '+/' '-_' \
    | tr -d '='
}

decode_base64url() {
  value="$(printf '%s' "$1" | tr '_-' '/+')"
  mod=$(( ${#value} % 4 ))
  if [ "$mod" -eq 2 ]; then
    value="${value}=="
  elif [ "$mod" -eq 3 ]; then
    value="${value}="
  elif [ "$mod" -eq 1 ]; then
    echo "Invalid base64url value" >&2
    exit 1
  fi
  printf '%s' "$value" | openssl base64 -d -A
}

extract_query_param() {
  raw_value="$(printf '%s\n' "$1" | tr '&' '\n' | sed -n "s/^$2=//p" | head -n 1)"
  if [ -n "$raw_value" ]; then
    urldecode "$raw_value"
  fi
}

open_browser() {
  if [ "$AUTO_OPEN" != "true" ]; then
    return 0
  fi
  if command -v open >/dev/null 2>&1; then
    open "$1" >/dev/null 2>&1 || true
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$1" >/dev/null 2>&1 || true
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --base-url) BASE_URL="$2"; shift 2 ;;
    --realm) REALM="$2"; shift 2 ;;
    --client-id) CLIENT_ID="$2"; shift 2 ;;
    --redirect-uri) REDIRECT_URI="$2"; shift 2 ;;
    --scope) SCOPE="$2"; shift 2 ;;
    --idp-hint) IDP_HINT="$2"; shift 2 ;;
    --no-open) AUTO_OPEN=false; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unexpected argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

require_cmd curl
require_cmd jq
require_cmd openssl
require_cmd nc

redirect_host="$(printf '%s' "$REDIRECT_URI" | sed -E 's#^[a-z]+://([^/:]+).*#\1#')"
redirect_port="$(printf '%s' "$REDIRECT_URI" | sed -nE 's#^[a-z]+://[^/:]+:([0-9]+).*#\1#p')"

if [ -z "$redirect_host" ] || [ -z "$redirect_port" ]; then
  echo "Could not parse redirect URI host/port from: $REDIRECT_URI" >&2
  echo "Use a redirect URI with an explicit numeric port, e.g. http://127.0.0.1:18080/callback" >&2
  exit 1
fi

code_verifier="$(random_urlsafe)"
code_challenge="$(pkce_challenge "$code_verifier")"
state="$(random_urlsafe)"
nonce="$(random_urlsafe)"

auth_endpoint="${BASE_URL%/}/realms/${REALM}/protocol/openid-connect/auth"
token_endpoint="${BASE_URL%/}/realms/${REALM}/protocol/openid-connect/token"
discovery_endpoint="${BASE_URL%/}/realms/${REALM}/.well-known/openid-configuration"

discovery_json="$(curl -fsS "$discovery_endpoint" 2>/dev/null || true)"
if [ -n "$discovery_json" ]; then
  discovered_auth_endpoint="$(printf '%s' "$discovery_json" | jq -r '.authorization_endpoint // empty')"
  discovered_token_endpoint="$(printf '%s' "$discovery_json" | jq -r '.token_endpoint // empty')"
  if [ -n "$discovered_auth_endpoint" ]; then
    auth_endpoint="$discovered_auth_endpoint"
  fi
  if [ -n "$discovered_token_endpoint" ]; then
    token_endpoint="$discovered_token_endpoint"
  fi
fi

auth_url="${auth_endpoint}?client_id=$(urlencode "$CLIENT_ID")&redirect_uri=$(urlencode "$REDIRECT_URI")&response_type=code&scope=$(urlencode "$SCOPE")&code_challenge=$(urlencode "$code_challenge")&code_challenge_method=S256&state=$(urlencode "$state")&nonce=$(urlencode "$nonce")"
if [ -n "$IDP_HINT" ]; then
  auth_url="${auth_url}&kc_idp_hint=$(urlencode "$IDP_HINT")"
fi

tmp_request="$(mktemp -t wallet-connector-oidc-request.XXXXXX)"
cleanup() {
  rm -f "$tmp_request" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

echo "Listening for the authorization redirect on ${redirect_host}:${redirect_port} ..."
(
  {
    printf 'HTTP/1.1 200 OK\r\n'
    printf 'Content-Type: text/plain; charset=utf-8\r\n'
    printf 'Connection: close\r\n'
    printf '\r\n'
    printf 'Wallet login completed. Return to the terminal.\r\n'
  } | nc -l "$redirect_host" "$redirect_port" > "$tmp_request"
) &
listener_pid=$!

echo "Open this URL to start the wallet flow:"
echo "$auth_url"
if [ "$auth_endpoint" != "${BASE_URL%/}/realms/${REALM}/protocol/openid-connect/auth" ]; then
  echo "Resolved browser-facing authorization endpoint from OIDC discovery."
fi
open_browser "$auth_url"

wait "$listener_pid"

request_path="$(
  tr -d '\r' < "$tmp_request" \
    | sed -n '1s#^GET \([^ ]*\) HTTP/1\.[01]$#\1#p'
)"
if [ -z "$request_path" ]; then
  echo "No authorization redirect captured." >&2
  exit 1
fi

query_string=""
case "$request_path" in
  *\?*) query_string="${request_path#*\?}" ;;
esac

if [ -z "$query_string" ]; then
  echo "Redirect did not contain a query string: $request_path" >&2
  exit 1
fi

returned_state="$(extract_query_param "$query_string" state)"
if [ "$returned_state" != "$state" ]; then
  echo "State mismatch in authorization response." >&2
  exit 1
fi

auth_code="$(extract_query_param "$query_string" code)"
auth_error="$(extract_query_param "$query_string" error)"

if [ -n "$auth_error" ]; then
  echo "Authorization failed: $auth_error" >&2
  error_description="$(extract_query_param "$query_string" error_description)"
  if [ -n "$error_description" ]; then
    echo "$error_description" >&2
  fi
  exit 1
fi

if [ -z "$auth_code" ]; then
  echo "No authorization code returned." >&2
  exit 1
fi

token_response="$(curl -fsS \
  -X POST "$token_endpoint" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode "grant_type=authorization_code" \
  --data-urlencode "client_id=$CLIENT_ID" \
  --data-urlencode "redirect_uri=$REDIRECT_URI" \
  --data-urlencode "code=$auth_code" \
  --data-urlencode "code_verifier=$code_verifier")"

id_token="$(printf '%s' "$token_response" | jq -r '.id_token // empty')"
if [ -z "$id_token" ]; then
  echo "Token response did not contain an id_token." >&2
  printf '%s\n' "$token_response" | jq .
  exit 1
fi

payload_segment="$(printf '%s' "$id_token" | cut -d. -f2)"
payload="$(decode_base64url "$payload_segment")"

echo ""
echo "Decoded id_token payload:"
printf '%s\n' "$payload" | jq .
