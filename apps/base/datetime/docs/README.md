# Base DateTime

Base DateTime owns Bilimbi's timestamp display policy (#459): the
company/local/UTC mode, the two Settings definitions behind it, and the
server-authorized display metadata presentation renders with. It has no table
or migration; values remain in canonical `base_settings`. It is a policy
boundary, not date arithmetic — business modules keep their stored-timestamp
and deadline semantics, and canonical storage stays UTC.

## The two settings

- `localization.timezone` — company-scoped IANA identifier, default `UTC`.
  Declared here as the policy owner; Core Company keeps the management
  surface and resolution, writing through the public Settings API under its
  own `admin.company.update` capability. Base never queries Core.
- `ui.timezone.mode` — user-scoped `company | local | utc`, default
  `company`. Mutation derives the account from the authenticated context;
  a request can never name another user.

## Display resolution

`Bilimbi.Base.DateTime.display/2` takes the account's explicit Settings scope
and the company scope and returns a `%Display{}` — mode, company time zone,
resolved locale, and the time zone database module as a value. The web edge
resolves it once per request/LiveView process and stores it in
`Bilimbi.Base.UI.DateTimeDisplay` (the `Gettext.put_locale/2` pattern), so
every `<.datetime>` on a screen renders in the same mode and no user's
context leaks into another process.

Rendering semantics, preserved from the source:

- `nil` renders `—`;
- `:local` keeps the truthful UTC-labelled server text and lets the browser
  hook enhance it into the device's zone;
- `:company` shifts server-side into the company IANA zone and renders final
  text labelled with the zone abbreviation — an unconvertible zone falls
  back to the truthful UTC text rather than guessing;
- `:utc` renders the stored UTC value as final text.

The no-JavaScript fallback in every mode is the server text itself.
Compatible `NaiveDateTime` values are explicitly interpreted as UTC.

## Time zone database

Validation and shifting run against `TimeZoneInfo.TimeZoneDatabase`, the
explicit-database idiom `base/schedule` established. Elixir's default
UTC-only database cannot convert zones and is never assumed to. The database
module travels inside `%Display{}` as a value, so Base UI needs no dependency
on the package.
