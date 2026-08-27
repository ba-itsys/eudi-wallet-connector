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
- Trust material provider alias: `eudi-pid-trust`
- OIDC client: `wallet-rp`
- OIDC client scope: `wallet-pid`
- Login theme: `wallet-connector`
- DCQL request: built from the configured OID4VP mappers
- Requested credential: the German PID as SD-JWT VC, `vct` `urn:eudi:pid:de:1`, under the DCQL credential id `pid`

The connector requests the SD-JWT PID only. The mDoc PID (`eu.europa.ec.eudi.pid.1`) is not requested,
so a wallet holding the PID in mDoc form alone cannot sign in.

## Transient Users Only

This connector is set up for transient users:

- Docker starts Keycloak with `--features=transient-users`
- The OID4VP IdP config contains `doNotStoreUsers=true`

This means:

- no Keycloak user is created for wallet logins
- the session is only used to carry verified credential data
- token claims must come from session notes, not from persisted user attributes

## Claim Mapping

The identity-provider mappers write wallet claims into session attributes, and the mappers are also what
builds the DCQL request. The claim names follow the SD-JWT VC data identifiers of the
[German PID credential](https://demo.pid-provider.bundesdruckerei.de/credential-claims).
The IdP config configures no `principalAttributes`, because transient users make the subject a per-login value.

| Credential claim | Session attribute | Token claim |
| --- | --- | --- |
| `given_name` | `wallet.given_name` | `given_name` |
| `family_name` | `wallet.family_name` | `family_name` |
| `birthdate` | `wallet.birthdate` | `birthdate` |
| `address.street_address` | `wallet.address.street_address` | `address.street_address` |
| `address.locality` | `wallet.address.locality` | `address.locality` |
| `address.postal_code` | `wallet.address.postal_code` | `address.postal_code` |
| `address.country` | `wallet.address.country` | `address.country` |
| `place_of_birth.locality` | `wallet.place_of_birth` | `place_of_birth` |

The German PID carries further claims, among them `birth_name`, `title`, `also_known_as`, `nationalities`,
`age_equal_or_over.*`, `address.region`, `issuing_authority`, `issuing_country`, `source_document_type`
and `date_of_expiry`.
This connector does not request them. Adding one means adding an
`oid4vp-sd-jwt-user-session-attribute-idp-mapper` with the claim path, plus a matching
`oidc-usersessionmodel-note-mapper` on the `wallet-pid` client scope — and, for a real sandbox wallet,
a registration certificate that entitles the relying party to that claim.

By default, the claims are added to:

- `id_token`
- `userinfo`

They are not added to the access token.

## Local Wallet vs Sandbox

`scripts/setup-local-realm.sh` builds [generated/realm-wallet-connector-local.json](../generated/realm-wallet-connector-local.json) from the base realm.

Both modes write the wallet-facing protocol settings on `eudi-pid` and the trust list on `eudi-pid-trust`.

Local wallet mode:

- `clientIdScheme=plain`
- `responseMode=direct_post`
- no verifier certificate
- `eudi-pid-trust.trustListUrl` points to the local `oid4vc-dev` PID trust list through `host.docker.internal`
- `eudi-pid-trust.trustListLoTEType=http://uri.etsi.org/19602/LoTEType/local`
- `sslRequired=none`

Sandbox mode:

- `clientIdScheme=x509_hash`
- `responseMode=direct_post.jwt`
- the verifier certificate and `verifierInfo` are injected from the SPRIND sandbox files
- `eudi-pid-trust.trustListUrl` points to the BMI test trust list for PID providers
- `eudi-pid-trust.trustListLoTEType=http://uri.etsi.org/19602/LoTEType/EUPIDProvidersList`

`x509_hash` plus `direct_post.jwt` is what wallets following the high assurance profile expect.
The provider dropped its `enforceHaip` switch in 0.9.0; the profile is now expressed by these settings alone.

This connector does not enforce OID4VP `trusted_authorities` constraints in its wallet request:
`eudi-pid-trust` keeps `advertiseTrustedAuthorities` empty in both modes.
The trust list is still used for verifier-side issuer signature validation.

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
