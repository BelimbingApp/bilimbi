# Working under apps/

Read this before editing a LiveView, a template, or a test. The component that can make a mistake impossible owns the rule: its comment is the text to follow, and `DESIGN.md` is the design source. This note only holds what no component owns.

## List filters and pagination

Use `<.filter_toolbar>` and `<.pagination>` for an operational list. A hand-written filter form or Previous/Next row is how Performance, Menu Inspector, Schedule history, and Database Queries drifted apart. The comments on `filter_toolbar/1` and `pagination/1` in `apps/base/ui/lib/ui/components.ex` own the framing; the URL contract is `DESIGN.md` "Pagination controls". A pager over unsaved editor state, such as database-query results, still uses `<.pagination>` and must not reload the saved record when the page changes.

## LiveView bindings

Put `phx-change` on the `<form>`, and `phx-submit` aimed at the same handler. A control that is not inside a form uses `phx-keyup`. `phx-input` is not a LiveView binding and silently does nothing, which is how both search boxes on the user page shipped broken; without `phx-submit`, Enter native-GETs the page and reloads it.

## Messages

Flash `:success` only for a completed write. `:info` informs and confirms nothing. When one call can do either, take the kind from that outcome: a Countries update that did not update was rendered as a green success because the kind was fixed in advance. A refusal names its real cause. The Settings page blamed the modules when the reason was a permission. Kinds and timing live in `DESIGN.md` "Honest feedback" and in the docs on `flash_group/1` and `panel_notice/1`.

## Withheld controls

If a button or editor is absent, the page says why and what to do next, through `empty_state/1` (`title`, `reason`, or `forbidden`) or `<.table>`'s `<:empty>` slot. The Roles picker, a settings group, and an archived-company account each hid a control until the page said why.

## Clocks

Render a timestamp with `<.datetime>`, which follows the reader's saved clock, streamed rows included. Pass `display` only to pin one instant to a context of your own. A value inside an audit diff uses `precision={:second}` so two edits in one minute stay distinct; that call is `Bilimbi.Base.Audit.Web.MutationDiff.diff_value/1`.

## Read-first pages

A record's page reads first and edits in place. There is no separate Edit button, including a record whose only page was a form. Short facts commit through `<.inline_edit>`, multi-line facts through `<.inline_long_text>`, and the outcome bookkeeping is `Bilimbi.Base.UI.CommitStatus`, passed back as `status`. See `DESIGN.md` "Read-first detail pages" and "Inline editing".

## Tests

Assert what the running system does. Do not add a test that reads or pattern-matches a source file to prove a bug is gone: two did that and passed while the problem they claimed to catch was still in the tree. A security or database boundary makes PostgreSQL do the refusing; for the SQL console that is `QueryExecutor`'s `READ ONLY` transaction. See `apps/base/database/AGENTS.md`.

## Routes

Let `BilimbiWeb.RouteOverlap` check the compiled router for route conflicts. A route manifest alone misses direct host routes; injected routes carry their descriptor owner and layer in Phoenix route metadata. See `apps/web/lib/bilimbi_web/discovered_routes.ex`.

## Follow-up

A caller can still hide a control with `:if` and no `empty_state`. The component only speaks when it is used. Moving that into something a caller cannot skip is product work, and it is not done here.

## Maintaining this file

Keep this note short. Point at the component, its comment, or DESIGN.md; do not copy them.
