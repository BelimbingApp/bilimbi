# Base UI

**Stable module ID:** `base/ui` · **Layer:** Base · required

Owns the shared presentation contracts every UI-bearing module needs:
layouts, core components, the `use Bilimbi.Base.UI, :live_view` facade,
`Bilimbi.Base.UI.IconRegistry` for named action icons and product glyphs,
and `RouteContract` for compile-time `~p` verification.

The LiveView and LiveComponent facades wrap `handle_event/3` so an unexpected
action exception is logged and shown as an honest error flash without replacing
the mounted screen. Exceptions that carry deliberate framework outcomes, such
as authorization denial, invalid changesets, and missing records, still
propagate. Rendering and other lifecycle callbacks are not recovered.

This package is dependency-light. It depends on Phoenix libraries, `base/menu`,
and `base/module_registry` only — never on Tenancy, Authz, Session, or `:web`.
Authentication `on_mount` hooks stay in `BilimbiWeb.UserAuth`.

Call sites name user-facing actions through `IconRegistry` (`create`, `edit`,
`delete`, …) rather than raw `hero-*` strings. Logout is the exception and
keeps `hero-arrow-right-on-rectangle`. Destination navigation has no single
action glyph; menu contributions keep their own icons. A name that is neither
registered nor `hero-*`-prefixed raises instead of rendering a fallback glyph,
so a name that reaches `<.icon>` from stored data is filtered through
`IconRegistry.renderable?/1` first; that module's doc owns the lookup contract.

Read-first detail pages report each in-place commit through `<.inline_edit>`
and `<.commit_status>`; `Bilimbi.Base.UI.CommitStatus` owns the bookkeeping
those components render — the `:field_status` assign, the rule that "Saved"
belongs to the most recent commit only, the refusal wording and the
rejected-value truncation — and its moduledoc lists what an adopting page
does.
