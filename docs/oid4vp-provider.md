# OID4VP Provider

This repository uses the upstream `keycloak-extension-oid4vp` provider as a Keycloak identity provider. This repo does not contain custom verifier code. It only configures the provider for a German PID wallet login and maps the verified claims into OIDC tokens.

For the full upstream reference, see:

- [keycloak-extension-oid4vp README](https://github.com/ba-itsys/keycloak-extension-oid4vp/blob/main/README.md)
- [Upstream provider configuration reference](https://github.com/ba-itsys/keycloak-extension-oid4vp/blob/main/docs/configuration.md)
- [Upstream request-flow walkthrough](https://github.com/ba-itsys/keycloak-extension-oid4vp/blob/main/docs/request-flow.md)

## How The Provider Is Used Here

The provider is imported as a Keycloak identity provider in [config/realm-wallet-connector-base.json](../config/realm-wallet-connector-base.json):

- alias: `eudi-pid`
- display name: `EUDI PID`
- provider type: `oid4vp`
- first broker login flow: `wallet transient first broker login`
- browser flow entry: the realm's default browser flow immediately redirects into this provider

In other words, Keycloak is only the OAuth/OIDC shell. The wallet presentation and verification logic comes from the upstream OID4VP provider.

## Transient Connector Mode

The provider supports stored users and transient users. This repository uses transient users:

- Keycloak is started with the `transient-users` feature enabled
- the IdP config sets `doNotStoreUsers=true`

This means:

- no brokered Keycloak users are stored
- the provider creates a transient login identity for the session only
- credential data must be passed through session notes and token mappers

So this connector acts more like a verifier bridge than a persistent IAM.

## Credential Request Configuration

The upstream provider can build DCQL automatically from its OID4VP mappers, or it can use an explicit `dcqlQuery`. This repository uses mapper-driven DCQL for the default PID setup.

The default provider configuration asks for German PID credentials in two formats:

- SD-JWT VC type `urn:eudi:pid:de:1`
- mDoc type `eu.europa.ec.eudi.pid.1`

The configured IdP mappers define how claims are copied into session notes after verification:

- which credential format is expected
- which credential type is allowed
- which claim path should be read
- which Keycloak session note receives the value

The configured mappers are the credential request used by this connector.
The user identifier claim fields are left empty in the default config.

## Flow Settings

The upstream provider supports same-device and cross-device wallet login. This repository enables both:

- `sameDeviceEnabled=true`
- `crossDeviceEnabled=true`
- `walletScheme=openid4vp://`

So the login page can show both:

- a same-device deep link button
- a cross-device QR code

The page layout comes from the provider theme fragments plus the local login-theme overrides in this repo.

## Verification and Trust Settings

The upstream provider exposes verifier settings such as `responseMode`, `clientIdScheme`, HAIP handling, trust-list use, and `trustedAuthoritiesMode`.

This repository keeps the trust-authorities mode disabled:

- `trustedAuthoritiesMode=none`

The generated local realm then switches between two common verifier profiles:

Local wallet mode from [scripts/setup-local-realm.sh](../scripts/setup-local-realm.sh):

- `clientIdScheme=plain`
- `responseMode=direct_post`
- `enforceHaip=false`
- `trustListUrl` points to the local wallet or dev trust list

Sandbox mode from [scripts/setup-local-realm.sh](../scripts/setup-local-realm.sh):

- `clientIdScheme=x509_hash`
- `responseMode=direct_post.jwt`
- `enforceHaip=true`
- the verifier certificate PEM and `verifierInfo` are injected from local SPRIND sandbox files

For the meaning of those settings, use the upstream configuration reference linked above. That is the source of truth for provider behavior.

## Claim Mapping In This Connector

The upstream provider offers two mapper types:

- `OID4VP Claim to User Attribute`
- `OID4VP Claim to User Session Note`

This repository uses session-note mappers so verified wallet data can flow into OIDC tokens without creating persistent users.

The mapping path is:

1. wallet credential claim
2. OID4VP IdP mapper
3. Keycloak user session note
4. `wallet-pid` client-scope protocol mapper
5. `id_token` and `userinfo`

Examples from this repo:

| Credential claim | Session note | Token claim |
| --- | --- | --- |
| `given_name` | `wallet.given_name` | `given_name` |
| `family_name` | `wallet.family_name` | `family_name` |
| `birthdate` or `birth_date` | `wallet.birthdate` | `birthdate` |
| `birth_place` or `place_of_birth/locality` | `wallet.place_of_birth` | `place_of_birth` |

## Multiple Wallet Providers

The upstream provider does not limit you to one OID4VP IdP. You can configure multiple provider instances with different aliases, DCQL mapper sets, or verifier settings.

That is why this repository uses the credential-specific alias `eudi-pid` instead of a generic `oid4vp` alias.

If you add further OID4VP IdPs, you can select them explicitly through:

- `kc_idp_hint=<alias>`

The default browser flow in this repo currently auto-selects `eudi-pid`.
