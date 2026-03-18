# Configuration

This connector is a Keycloak realm import plus the upstream provider jar. This repository does not contain custom Java code.

For the provider-level settings exposed by `keycloak-extension-oid4vp`, see [OID4VP Provider](oid4vp-provider.md).

## Connector Shape

- Keycloak is the OAuth/OIDC endpoint for relying parties.
- The OID4VP provider is configured as an identity provider with `doNotStoreUsers=true`.
- The browser flow only redirects to the configured wallet provider. There is no local Keycloak login step.
- A small first-broker-login flow is imported so transient wallet logins do not ask the user to create or update an account.
- Wallet claims are written to user session notes.
- The `wallet-pid` client scope maps those session notes into `id_token` and `userinfo`.
- No brokered users are stored after the session ends.

## Realm Defaults

The base realm file is [config/realm-wallet-connector-base.json](../config/realm-wallet-connector-base.json).

Default values:

- Realm name: `wallet-connector`
- Identity provider alias: `eudi-pid`
- OIDC client: `wallet-rp`
- OIDC client scope: `wallet-pid`
- Login theme: `wallet-connector`
- DCQL request: built from the configured OID4VP mappers
- Allowed credential types:
  - `urn:eudi:pid:de:1` for SD-JWT VC
  - `eu.europa.ec.eudi.pid.1` for mDoc

## Transient Users Only

This connector is set up for transient users:

- Docker starts Keycloak with `--features=transient-users`
- The OID4VP IdP config contains `doNotStoreUsers=true`

This means:

- no Keycloak user is created for wallet logins
- the session is only used to carry verified credential data
- token claims must come from session notes, not from persisted user attributes

## Claim Mapping

The identity-provider mappers write wallet claims into shared session-note keys for both supported PID formats.
The default IdP config leaves the user identifier claim fields empty and builds the DCQL request from the configured mappers.

Examples:

| Credential claim | Session note | Token claim |
| --- | --- | --- |
| `given_name` | `wallet.given_name` | `given_name` |
| `family_name` | `wallet.family_name` | `family_name` |
| `birthdate` or `birth_date` | `wallet.birthdate` | `birthdate` |
| `address/street_address` or `resident_street` | `wallet.address.street_address` | `address.street_address` |
| `birth_place` or `place_of_birth/locality` | `wallet.place_of_birth` | `place_of_birth` |
| `issuing_country` | `wallet.issuing_country` | `issuing_country` |

The `wallet-pid` client scope then maps these session notes to token claims:

- standard OIDC claims:
  - `given_name`
  - `family_name`
  - `birthdate`
  - `address.*`
- top-level PID claims such as `place_of_birth`, `issuing_country`, `issuing_authority`, and `expiry_date`

By default, the claims are added to:

- `id_token`
- `userinfo`

They are not added to the access token.

## Local Wallet vs Sandbox

`scripts/setup-local-realm.sh` builds [generated/realm-wallet-connector-local.json](../generated/realm-wallet-connector-local.json) from the base realm.

Local wallet mode:

- `clientIdScheme=plain`
- `responseMode=direct_post`
- `trustedAuthoritiesMode=none`
- no verifier certificate
- the trust list points to `oid4vc-dev`

Sandbox mode:

- `clientIdScheme=x509_hash`
- `responseMode=direct_post.jwt`
- `trustedAuthoritiesMode=none`
- `enforceHaip=true`
- the verifier certificate and `verifierInfo` are injected from the SPRIND sandbox files

## Customizing The Relying-Party Client

The default `wallet-rp` client is only a demo starting point.

Adjust at least:

- `redirectUris`
- `webOrigins`
- public vs confidential client mode
- assigned client scopes

The realm's default browser flow auto-selects the PID provider alias `eudi-pid`.
In practice, the flow only runs the IdP redirector, so every authentication attempt starts a fresh wallet login.
If you configure multiple OID4VP identity providers with different DCQL queries or credential types, use `kc_idp_hint=<alias>` to choose one.
