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
PROJECT_POM="${ROOT_DIR}/pom.xml"
OUTPUT_DIR="${ROOT_DIR}/target/providers"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

maven_eval() {
  expression="$1"
  mvn -q -f "$PROJECT_POM" -DforceStdout help:evaluate -Dexpression="$expression" | tail -n 1
}

mvn_dep() {
  goal="$1"
  shift
  mvn -q -f "$PROJECT_POM" "org.apache.maven.plugins:maven-dependency-plugin:${DEPENDENCY_PLUGIN_VERSION}:${goal}" "$@"
}

maven_repo_path() {
  mvn -q -f "$PROJECT_POM" -DforceStdout help:evaluate -Dexpression=settings.localRepository | tail -n 1
}

copy_jar() {
  mvn_dep "copy" -Dartifact="$1:$2:$3" -DoutputDirectory="$OUTPUT_DIR"
}

require_cmd mvn

if [ ! -f "$PROJECT_POM" ]; then
  echo "Project pom not found: $PROJECT_POM" >&2
  exit 1
fi

DEPENDENCY_PLUGIN_VERSION="${DEPENDENCY_PLUGIN_VERSION:-$(maven_eval maven-dependency-plugin.version)}"
OID4VP_GROUP_ID="${OID4VP_GROUP_ID:-$(maven_eval oid4vp.groupId)}"
OID4VP_ARTIFACT_ID="${OID4VP_ARTIFACT_ID:-$(maven_eval oid4vp.artifactId)}"
OID4VP_VERSION="${OID4VP_VERSION:-$(maven_eval oid4vp.version)}"

MAVEN_REPO="$(maven_repo_path)"
if [ -z "$MAVEN_REPO" ] || [ ! -d "$MAVEN_REPO" ]; then
  echo "Could not determine Maven local repository path." >&2
  exit 1
fi

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

echo "==> Preparing Keycloak provider jar in target/providers/"

copy_jar "$OID4VP_GROUP_ID" "$OID4VP_ARTIFACT_ID" "$OID4VP_VERSION"

echo "    Provider jar:"
find "$OUTPUT_DIR" -maxdepth 1 -type f -name '*.jar' -print | sed "s#^${ROOT_DIR}/##" | sort
