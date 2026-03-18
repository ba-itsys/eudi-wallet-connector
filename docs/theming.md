# Theming

The wallet connector uses a normal Keycloak login theme. This repository ships a filesystem theme at [themes/wallet-connector/login/theme.properties](../themes/wallet-connector/login/theme.properties) with CSS in [themes/wallet-connector/login/resources/css/wallet-connector.css](../themes/wallet-connector/login/resources/css/wallet-connector.css).

The realm import already sets:

- `loginTheme=wallet-connector`

## Corporate Design Customization

For simple branding changes, update the CSS file and keep the template from the provider:

- colors
- fonts
- logo background
- card spacing
- button styling

That is enough if you only want the wallet page to match your corporate design.

## Full QR/Same-Device Page Override

If you want to fully redesign the wallet page, add this file to your custom login theme:

- `themes/<your-theme>/login/login-oid4vp-idp.ftl`

Use the template from the OID4VP provider as a starting point. When you override it, keep these parts:

- the hidden form fields for `vp_token`, `response`, `error`, and `error_description`
- the `sameDeviceWalletUrl` link
- the QR code image built from `qrCodeBase64`
- the `oid4vp-cross-device-sse-config` element
- the SSE script include

If any of those are removed, the login flow can break.

## Theme Deployment

The Docker setup mounts the whole [themes](../themes) directory into `/opt/keycloak/themes`, so theme changes are picked up on the next container start.
