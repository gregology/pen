# AI Penetration Testing

A Dockerized penetration platform to test my apps for vulnerabilities.

## Principles

### Use VPN to mimick external attacks

All network requests go though a VPN so that the testing mimicks external attacks. This way we're not miss identifying internal penetrations as external vulnerabilities.

### Do not use initiative

The attack surface should not be broadened without explicit confirmation from a human.
