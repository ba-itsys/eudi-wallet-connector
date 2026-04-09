//go:build tools
// this file purely exists to prevent go mod tidy from removing the dependency (which in turn is just used to allow dependabot-updates).

package tools

import _ "github.com/dominikschlosser/oid4vc-dev"
