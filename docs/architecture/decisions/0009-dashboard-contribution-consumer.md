# ADR 0009: Dashboard widget catalogue as a fourth contribution consumer

**Document Type:** Architecture Decision Record
**Status:** Accepted
**Scope:** Contribution consumer for platform dashboard widgets
**Last Updated:** 2026-08-18

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

## Decision

`:dashboard` is adopted as a **peer consumer** in the same contribution
contract. It shares the identical snapshot lifecycle, validation guard, and
deterministic ordering rules as `:settings`, `:authz`, and `:menu`.

1. `ContributionProvider` accepts `:dashboard` as a valid consumer key.
2. `ContributionRegistry` registers `Bilimbi.Base.Dashboard.ContributionValidator`
   as the validator for the `:dashboard` consumer, matching the pattern of the
   three initial consumers.
3. A widget contribution is a **list of maps** where each map declares `:id`,
   `:label`, and optional `:size`, `:order`, and `:capability` fields. The
   validator rejects duplicates, enforces the shape, and sorts deterministically
   by `:order` then `:id`.
4. Widget contributions do not carry render modules. Rendering is owned by the
   dashboard LiveView adapter. Widget implementors may implement the
   `Bilimbi.Base.Dashboard.Widget` behaviour to declare assign sets and refresh
   intervals for auto-refresh scheduling.

## Rationale

- **Extension pattern is not new.** `ContributionProvider` already carries three
  consumers; the infrastructure to add a fourth is four lines (one type update,
  one validator entry). Adding `:dashboard` does not redesign the contract.
- **Module ownership is preserved.** Any installed module may contribute widgets
  by adding a `:dashboard` key to its `contributions/0` return value, exactly as
  it adds `:menu` or `:authz` entries. No central registry edit is required.
- **Rendering decoupling is deliberate.** Widget catalogue entries carry
  metadata, not rendering logic. The LiveView adapter resolves known widget IDs
  into built-in stat cards. Future modules may supply a `Bilimbi.Base.Dashboard.Widget`
  implementation referenced by `widget.id` to provide their own rendering.

## Consequences

- A widget contributed by a Domain or Extension module that lacks a
  corresponding render adapter in the dashboard LiveView renders as a
  labelled placeholder card. This is honest: the widget is present in the
  catalogue but has no adapter yet.
- The `:dashboard` key is available to any installed module from this ADR
  forward. Existing modules that do not declare a `:dashboard` key are
  unaffected.
