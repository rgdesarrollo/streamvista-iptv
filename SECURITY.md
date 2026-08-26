# Security policy

## Supported versions

Security fixes are applied to the latest release branch only.

## Reporting a vulnerability

Do not open a public issue for a suspected vulnerability or exposed credential. Contact the repository owner privately with a description, affected version, and reproduction steps. Rotate any credentials that may have been exposed.

## Release checklist

- Use HTTPS-only playlist and portal addresses.
- Never commit `android/key.properties`, `.jks`/`.keystore` files, credentials, playlists, or Firebase service-account files.
- Sign Android releases with a protected, backed-up upload key.
- Code-sign Windows installers before public distribution.
- Test playback with authorised content on each target device.
- Review Firebase rules and deploy pairing infrastructure only in a project you control.
