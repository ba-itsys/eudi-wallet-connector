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

A second identity provider carries the trust material:

- alias: `eudi-pid-trust`
- display name: `German PID Trust Material`
- provider type: `etsi-trust-list`

It never authenticates users and is hidden from login pages. `eudi-pid` references it through
`trustMaterialIdps`. Since provider version 0.9.0 the trust list no longer lives on the OID4VP provider
itself, so trust can be resolved per credential type.

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

The upstream provider builds the DCQL query from its OID4VP mappers. This repository uses mapper-driven
DCQL for the default PID setup.

The connector asks for the German PID in SD-JWT VC form only:

- `vct` `urn:eudi:pid:de:1`
- DCQL credential id `pid`, set explicitly through the mappers' `credential.id`
- `credentialSets` requires that one credential and carries the purpose text the wallet shows the user

The mDoc PID is not requested. The mapper type now decides the format, so requesting mDoc as well would
mean a second set of `oid4vp-mdoc-user-session-attribute-idp-mapper` entries.

Each mapper declares:

- the credential type (`credential.type`, the SD-JWT `vct`)
- the DCQL credential id it contributes to (`credential.id`)
- the claim path in dot notation (`claim`)
- the user session attribute that receives the value (`attribute`)

The configured mappers are the credential request used by this connector.
`principalAttributes` is left unset, because transient users make the subject a per-login value.

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

The upstream provider exposes verifier settings such as `responseMode`, `clientIdScheme` and
`requestUriMethodPost` on the OID4VP provider, and the trust material on the referenced trust provider.
`advertiseTrustedAuthorities` on `eudi-pid-trust` controls whether a `trusted_authorities` constraint is
added to the DCQL query. This connector keeps that constraint disabled in all generated local realm profiles.

Version 0.9.0 removed the `enforceHaip` switch. The high assurance profile is now expressed by
`clientIdScheme=x509_hash` together with `responseMode=direct_post.jwt`.
`requestUriMethodPost` stays `false`, so wallets fetch the request object with GET.

The generated local realm then switches between two common verifier profiles:

Local wallet mode from [scripts/setup-local-realm.sh](../scripts/setup-local-realm.sh):

- `clientIdScheme=plain`
- `responseMode=direct_post`
- `eudi-pid-trust.advertiseTrustedAuthorities` empty
- `eudi-pid-trust.trustListUrl` points to the Docker-reachable local `oid4vc-dev` PID trust list
- `eudi-pid-trust.trustListLoTEType=http://uri.etsi.org/19602/LoTEType/local`

Sandbox mode from [scripts/setup-local-realm.sh](../scripts/setup-local-realm.sh):

- `clientIdScheme=x509_hash`
- `responseMode=direct_post.jwt`
- `eudi-pid-trust.advertiseTrustedAuthorities` empty
- `eudi-pid-trust.trustListLoTEType=http://uri.etsi.org/19602/LoTEType/EUPIDProvidersList`
- the verifier certificate PEM and `verifierInfo` are injected from local SPRIND sandbox files

In local wallet mode, the trust list is used for verifier-side issuer signature validation only.
It is not advertised to the wallet as a `trusted_authorities` DCQL constraint.

For the meaning of those settings, use the upstream configuration reference linked above. That is the source of truth for provider behavior.

## Claim Mapping In This Connector

Since provider version 0.9.0 the mapper types are format-specific:

- `oid4vp-sd-jwt-user-attribute-idp-mapper`
- `oid4vp-sd-jwt-user-session-attribute-idp-mapper`
- `oid4vp-mdoc-user-attribute-idp-mapper`
- `oid4vp-mdoc-user-session-attribute-idp-mapper`

This repository uses `oid4vp-sd-jwt-user-session-attribute-idp-mapper` throughout, so verified wallet data
can flow into OIDC tokens without creating persistent users.

The mapping path is:

1. wallet credential claim
2. OID4VP IdP mapper
3. Keycloak user session attribute
4. `wallet-pid` client-scope protocol mapper
5. `id_token` and `userinfo`

Claim paths use dot notation. `address.locality` selects a nested claim; a literal dot is escaped as `\.`.

Examples from this repo:

| Credential claim | Session attribute | Token claim |
| --- | --- | --- |
| `given_name` | `wallet.given_name` | `given_name` |
| `family_name` | `wallet.family_name` | `family_name` |
| `birthdate` | `wallet.birthdate` | `birthdate` |
| `place_of_birth.locality` | `wallet.place_of_birth` | `place_of_birth` |

## Multiple Wallet Providers

The upstream provider does not limit you to one OID4VP IdP. You can configure multiple provider instances with different aliases, DCQL mapper sets, or verifier settings.

That is why this repository uses the credential-specific alias `eudi-pid` instead of a generic `oid4vp` alias.

If you add further OID4VP IdPs, you can select them explicitly through:

- `kc_idp_hint=<alias>`

The default browser flow in this repo currently auto-selects `eudi-pid`.
