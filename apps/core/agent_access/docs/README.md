# Agent connections

Core Agent Access owns OAuth device codes, per-person connections and opaque
access/refresh tokens (ADR 0021). All secrets are hashed with SHA-256 before
persistence and audit redacts those hash fields. Raw values leave the service
only in the initial device response or successful token response.

The built-in public client is `bilimbi-native`, with no secret or installation
registration. Device codes last ten minutes; polling starts at five seconds
and `slow_down` adds five seconds. Access tokens last at most one hour. The global Settings value
`agent_access.connection_days` sets new connections' length (90 days by default).
Both consent pages display the server-computed end time and accept no submitted
expiry. Existing connections retain their end times. Refresh tokens last until that
end date, rotate on every use, and a replay revokes the entire connection.
The parent connection row serializes redemption, refresh and replay; observation
locks it only when a stated agent ID is new.
Revocation and expiry apply to every access token in the connection.

Opening `/oauth/device?user_code=…` only fills the code field. A signed-in
person checks the code, reviews the stated agent and explicitly approves or
refuses. Impersonation and agent facets cannot manage connections. The person's
connections are at `/settings/agent-connections`; observed ID changes are shown
as “Also seen as”, keeping the newest 20 distinct IDs and never refusing the call.
An ID is self-reported and grants no authority.

The three new tables are Bilimbi-only migrations. `SchemaContract.tables/0`
contributes no adopted Belimbing baseline; `storage_tables/0` describes the
new storage for owner fixtures and structural verification.

The operator Settings page exposes `agent_access.oauth_requests_per_minute`
(default 60, per sender per endpoint per node). The built-in client ID and
one-hour access-token lifetime are protocol contracts, not operator secrets.

Deleting a person cascades their connections and credentials, while device
receipts retain their spent state without a connection. The new grant tables
therefore do not prevent the existing account-deletion workflow.
