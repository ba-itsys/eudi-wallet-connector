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

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

assert_jq() {
  file="$1"
  expression="$2"
  message="$3"

  if ! jq -e "$expression" "$file" >/dev/null; then
    echo "Assertion failed: $message" >&2
    echo "Expression: $expression" >&2
    echo "File: $file" >&2
    exit 1
  fi
}

write_sandbox_inputs() {
  pem_file="$TMP_DIR/sandbox.pem"
  verifier_info_file="$TMP_DIR/verifier-info.json"

  cat > "$pem_file" <<'EOF'
-----BEGIN CERTIFICATE-----
MIIBtest
-----END CERTIFICATE-----
EOF

  cat > "$verifier_info_file" <<'EOF'
[{"format":"jwt_vc_json","type":"PidCredential"}]
EOF
}

local_realm="$TMP_DIR/local-realm.json"
"$ROOT_DIR/scripts/setup-local-realm.sh" --local-wallet --output "$local_realm" >/dev/null

assert_jq "$local_realm" \
  '.identityProviders[0].config.trustedAuthoritiesMode == "none"' \
  "local wallet mode should not enforce trusted authorities"
assert_jq "$local_realm" \
  '.identityProviders[0].config.trustListUrl == "http://host.docker.internal:8087/api/trustlists/pid"' \
  "local wallet mode should point at the oid4vc-dev PID trust list"
assert_jq "$local_realm" \
  '.sslRequired == "none"' \
  "local wallet mode should not require HTTPS"
assert_jq "$local_realm" \
  '.identityProviders[0].config | has("x509CertificatePem") | not' \
  "local wallet mode should not inject a verifier certificate"
assert_jq "$local_realm" \
  '.identityProviders[0].config | has("verifierInfo") | not' \
  "local wallet mode should not inject sandbox verifier info"

write_sandbox_inputs
sandbox_realm="$TMP_DIR/sandbox-realm.json"
"$ROOT_DIR/scripts/setup-local-realm.sh" \
  --pem "$pem_file" \
  --verifier-info "$verifier_info_file" \
  --output "$sandbox_realm" >/dev/null

assert_jq "$sandbox_realm" \
  '.identityProviders[0].config.trustedAuthoritiesMode == "none"' \
  "sandbox mode should keep trusted authorities disabled by default"
assert_jq "$sandbox_realm" \
  '.identityProviders[0].config.x509CertificatePem | contains("BEGIN CERTIFICATE")' \
  "sandbox mode should inject the verifier certificate"
assert_jq "$sandbox_realm" \
  '.identityProviders[0].config.verifierInfo | fromjson | .[0].type == "PidCredential"' \
  "sandbox mode should inject verifier info JSON"

echo "setup-local-realm tests passed"
