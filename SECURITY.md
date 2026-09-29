# Security Policy

## Supported versions

Until Örtü reaches 1.0, security fixes are applied to the latest release only.

## Reporting a vulnerability

Do not open a public issue for a suspected vulnerability. Use GitHub's private vulnerability reporting feature on the repository's **Security** tab. Include affected versions, reproduction steps, impact, and any suggested mitigation.

Maintainers should acknowledge a report within seven days. Disclosure timing depends on severity and the availability of a safe release. Please avoid sharing the issue publicly until a fix or coordinated advisory is available.

## Security boundaries

Örtü is an offline decorative overlay, not a lock screen or security control. `.ortupack` files are untrusted data. They must remain subject to path, archive, file-count, size, type, image-dimension, and checksum validation and must never execute bundled code.

