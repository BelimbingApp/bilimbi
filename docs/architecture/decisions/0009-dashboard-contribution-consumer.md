# ADR 0009: Dashboard widget catalogue as a fourth contribution consumer

**Document Type:** Architecture Decision Record
**Status:** Accepted
**Scope:** Contribution consumer for platform dashboard widgets
**Last Updated:** 2026-10-04

## Context

ADR 0004 established three contribution consumers — `:settings`, `:authz`, and
`:menu` — sharing one ownership and discovery contract. Their eligibility,
snapshot lifecycle, and validation rules are defined in
`Bilimbi.Base.ModuleRegistry.ContributionProvider` and administered by
`ContributionRegistry`.

Bilimbi needs a widget-based dashboard (`docs/PORTING_STAGES.md` S3).
Belimbing provides a dashboard widget system that registers widgets through its
module configuration files (`app/Base/Dashboard/`), with user-customizable
layout persisted in the `ui.dashboard.layout` setting.

Decisions 3 to 5 are stated as amended on 2026-10-04; the amendment at the end
records what they replaced.

## Decision

`:dashboard` is adopted as a **peer consumer** in the same contribution
contract. It shares the identical snapshot lifecycle, validation guard, and
deterministic ordering rules as `:settings`, `:authz`, and `:menu`.

1. `ContributionProvider` accepts `:dashboard` as a valid consumer key.
2. `ContributionRegistry` registers `Bilimbi.Base.Dashboard.ContributionValidator`
   as the validator for the `:dashboard` consumer, matching the pattern of the
   three initial consumers.
3. A dashboard contribution is a **list of maps**. Each map declares `:id`,
   `:label`, and `:embed`, and optionally `:placement` (`:grid`, the default,
   or `:section` for a full-width block below the grid), `:size`, `:order`,
   `:capability`, and `:refresh_interval` in milliseconds. The validator
   rejects duplicates, enforces the shape, and sorts deterministically by
   `:order` then `:id`.
4. The module that contributes an entry also draws it. `:embed` names an
   embeddable panel (ADR 0006, "Amendment: embeddable panels") the same module
   declares in its `priv/web_routes.exs`. The dashboard renders each entry with
   `<.discovered_panel>` and names no contributing module.
5. The dashboard module owns its own screen.
   `Bilimbi.Base.Dashboard.Web.IndexLive` is contributed at `/dashboard`
   through `base/dashboard`'s `web:` route data, like any other module page.
   It owns the arrangement (which entries an account shows, in what order,
   persisted in the `ui.dashboard.layout` and `ui.dashboard.sections`
   settings) and the refresh timer. It reads no contributor's data.

## Rationale

- **Extension pattern is not new.** `ContributionProvider` already carries three
  consumers; the infrastructure to add a fourth is four lines (one type update,
  one validator entry). Adding `:dashboard` does not redesign the contract.
- **Module ownership is preserved.** Any installed module may contribute
  entries by adding a `:dashboard` key to its `contributions/0` return value
  and an embed entry to its route data, exactly as it adds `:menu` or `:authz`
  entries. No central registry edit is required, in the catalogue or in the
  rendering.
- **The data stays with its owner.** A company count is a Core Company read
  and a session count is a Base Session read. `base/dashboard` may not depend
  on Core, so a page that rendered those itself could only live in the host.
  Panels invert the UI ownership instead of the dependency: the read and its
  markup live with the owner, and the dashboard holds a string key.

## Consequences

- An entry whose panel is not installed renders the visible not-installed
  notice `<.discovered_panel>` gives every missing key. There is no placeholder
  card: a contribution without `:embed` fails validation at boot.
- The capability is stated twice on purpose, once on the dashboard entry and
  once on the embed entry. The first decides whether the entry is offered in
  the catalogue; the second lets the panel refuse wherever it is embedded.
  `apps/base/dashboard/web_test/dashboard_live_test.exs` holds the two equal
  for every installed entry.
- A contributor depends on `base/dashboard`, because a package that
  contributes to a consumer whose validator it cannot load fails its own
  contribution snapshot.
- A panel that wants fresh data reads again when the `refresh` count it is
  given changes; the page counts one refresh at the shortest non-zero
  `:refresh_interval` among the visible entries. A panel may ignore the count.
- The `:dashboard` key is available to any installed module from this ADR
  forward. Existing modules that do not declare a `:dashboard` key are
  unaffected.

## Amendment: the dashboard is module-owned (2026-10-04)

As first accepted, decision 4 said contributions carry no render modules and
"rendering is owned by the dashboard LiveView adapter". That adapter was
`BilimbiWeb.DashboardLive` in the host, which read Core Company, Core User,
Base Audit, Base Session and Base Perf directly and chose the markup from a
hard-coded map of widget ids. ADR 0006 §5 and §6 say the host owns no module's
LiveView and that a Base module with screens follows dir = module without
exception, so the two records disagreed.

This amendment resolves it in ADR 0006's favour. Decisions 3 to 5 above replace
the original decisions 3 and 4. The host no longer has a dashboard screen, a
`/dashboard` entry in its own route data, or the hard-coded `/dashboard` route
its discovered-route macro used to inject. The `Bilimbi.Base.Dashboard.Widget`
behaviour, whose only read callback was the refresh interval, is gone; the
interval is data on the contribution. The two sections below the grid, which
were literal branches in the host page, are contributions with
`placement: :section` and keep the ids stored in `ui.dashboard.sections`.

The top-bar notification bell is Core User's component. Core User contributes
it as the `"shell.notifications"` embed, and the shared shell
(`Bilimbi.Base.UI.Layouts.app/1`) renders it on every authenticated page. The
dashboard does not render it.
