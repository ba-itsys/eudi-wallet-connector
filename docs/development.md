# Development

## Prerequisites

- Java 21
- Maven 3.9+
- Go 1.26+ for local-wallet mode
- Docker
- `jq`
- `ngrok` for real-wallet testing

## Provider Download

This repository does not build a provider. It downloads the OID4VP uber-jar into `target/providers/`:

```bash
scripts/prepare-providers.sh
```

The download uses Maven with [pom.xml](../pom.xml). The artifact still must be available in your configured Maven repositories.

## Local Wallet Mode

```bash
scripts/dev.sh --local-wallet
```

This mode:

- downloads the provider jar
- installs `oid4vc-dev` into `target/bin/` with `go install` if it is not already available
- generates a realm import for `oid4vc-dev`
- starts an `oid4vc-dev` wallet with a PID
- can wrap Keycloak with the `oid4vc-dev` proxy
- starts Keycloak locally

Typical URLs:

- Keycloak: `http://localhost:9090` when proxy is enabled, otherwise `http://localhost:8080`
- Admin Console: `/admin`
- `oid4vc-dev` dashboard: `http://localhost:9091`
- wallet UI: `http://localhost:8086`

## Sandbox Mode

Here, "sandbox" means the German SPRIND wallet testing environment.

```bash
scripts/dev.sh
```

Expected files for the SPRIND sandbox in `sandbox/`:

- `sandbox-ngrok-combined.pem`
- `sandbox-verifier-info.json`

This mode:

- downloads the provider jar
- injects the SPRIND sandbox certificate and verifier metadata into the realm import
- starts ngrok
- starts Keycloak with `KC_HOSTNAME` set to the ngrok HTTPS URL

## Manual Commands

Generate a local-wallet realm:

```bash
scripts/setup-local-realm.sh --local-wallet
docker compose up
```

Generate a SPRIND sandbox realm:

```bash
scripts/setup-local-realm.sh --pem sandbox/sandbox-ngrok-combined.pem --verifier-info sandbox/sandbox-verifier-info.json
docker compose up
```

Run an end-to-end OIDC test against the running connector:

```bash
scripts/test-oidc-flow.sh --base-url http://localhost:8080
```

If you are using the `oid4vc-dev` proxy wrapper, point the script at `http://localhost:9090` instead.

The script reads `authorization_endpoint` and `token_endpoint` from OIDC discovery. If Keycloak runs behind ngrok, it will open the public HTTPS URL instead of `localhost`.

## Script Options

`scripts/dev.sh` supports:

- `--local-wallet`
- `--wallet-port <port>`
- `--pem <file>`
- `--verifier-info <file>`
- `--trust-list-url <url>`
- `--domain <name>`
- `--no-build`
- `--skip-realm`
- `--no-proxy`
- `--no-ngrok`
- `--ngrok-only`

## Notes

- `generated/` and `sandbox/` are gitignored.
- `docker compose up` expects `generated/realm-wallet-connector-local.json` to exist.
- The Keycloak admin user comes from Docker env vars, not a realm import user.
