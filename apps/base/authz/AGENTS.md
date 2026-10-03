# Base Authz changes

Declare operator-tenant-only authority through the contribution's
`platform_capabilities` list, which the shared evaluator enforces for direct,
role, `grant_all`, and named system-principal grants. Use route `operator:
true` for a screen whose whole workflow is platform-wide. See
[`docs/README.md`](docs/README.md#platform-capabilities) for the contract; do
not replace it with key-prefix checks or adapter-only authorization.
