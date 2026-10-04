# Working under apps/

Read this before editing a LiveView, a template, or a test. The component that can make a mistake impossible owns the rule: its comment is the text to follow, and `DESIGN.md` is the design source. This note holds only what no component owns.

## List filters and pagination

Use `<.filter_toolbar>` and `<.pagination>` for an operational list, which keeps its page, search, filters, sort and page size in URL state. Parse and patch that URL state with `Bilimbi.Base.UI.ListState`, and coerce a param with `Bilimbi.Base.UI.Params`. A private `to_int`, `positive_integer`, `nilify`, or `state_from_params` is the copy those replaced; their moduledocs own the contract. Two lists on one page use `ListState`'s `param_prefix` and `omit_defaults`, and rows a panel already holds in memory page through `ListState.paginate/2`; a private `build_page` or `normalize_table_state` is the copy those replaced. A country select takes `Geonames.country_options/0`, not a private `"Name (ISO)"` mapper over `list_countries/0`. A hand-written filter form or Previous/Next row is how Performance, Menu Inspector, Schedule history, and Database Queries drifted apart. The comments on `filter_toolbar/1` and `pagination/1` in `apps/base/ui/lib/ui/components/lists.ex` own the framing; the URL contract is `DESIGN.md` "Pagination controls". A pager over unsaved editor state, such as database-query results, still uses `<.pagination>` and must not reload the saved record when the page changes.

## LiveView bindings

Put `phx-change` on the `<form>`, and `phx-submit` aimed at the same handler. A control that is not inside a form uses `phx-keyup`. `phx-input` is not a LiveView binding and silently does nothing, which is how both search boxes on the user page shipped broken; without `phx-submit`, Enter native-GETs the page and reloads it.

## Messages

Flash `:success` only for a completed write. `:info` informs and confirms nothing. When one call can do either, take the kind from that outcome: a Countries update that did not update was rendered as a green success because the kind was fixed in advance. A refusal names its real cause. The Settings page blamed the modules when the reason was a permission. Kinds and timing live in `DESIGN.md` "Honest feedback" and in the docs on `flash_group/1` and `panel_notice/1`.

## Withheld controls

If a button or editor is absent, the page says why and what to do next, through `empty_state/1` (`title`, `reason`, or `forbidden`) or `<.table>`'s `<:empty>` slot. The Roles picker, a settings group, and an archived-company account each hid a control until the page said why. The component only speaks when it is used: a caller can still hide a control with `:if` and no `empty_state`, and nothing yet stops that.

## Clocks

Render a timestamp with `<.datetime>`, which follows the reader's saved clock, streamed rows included. Pass `display` only to pin one instant to a context of your own. The precision of a value inside an audit diff is `apps/base/audit/AGENTS.md`'s rule.

## Read-first pages

A record's page reads first and edits in place. There is no separate Edit button, including a record whose only page was a form. Short facts commit through `<.inline_edit>`, multi-line facts through `<.inline_long_text>`, and the outcome bookkeeping is `Bilimbi.Base.UI.CommitStatus`, passed back as `status`. A page's `save_field` handler is `CommitStatus.save_field/4` and its write's result goes through `CommitStatus.commit/4`; a private `refusal_message/3`, three-branch result `case` or generic-failure fallback is the copy those replaced, and the page keeps only its labels, `@failures` nouns, forbidden wording and the write itself. A schemaless form that shows a domain changeset's refusal calls `Bilimbi.Base.UI.FormErrors.copy/3`, not a private `copy_domain_errors`; it decides once what happens to an error on a field the form does not render. See `DESIGN.md` "Read-first detail pages" and "Inline editing".

## Who performed it

Take the person who performed an operation (an approver, an overrider, a requester) from `Bilimbi.Base.Tenancy.Scope.actor/1`, and ask whether they may do it with `Bilimbi.Base.Authz.can(scope, capability)`. Do not accept an actor or approver ID as an argument, and do not build one with `Authz.actor/5`, which checks whoever the caller names. When the record belongs to another company of the tenant, where `can/4` answers `:denied_company_scope`, ask `Authz.can_in_company(scope, company_id, capability, resource)`; rebuilding the actor at that company is the copy it replaced, and its doc owns the rule. A system actor names nobody, so refuse it. Under impersonation the actor carries `impersonator_id`; record it or refuse. Never call `Bilimbi.Base.Tenancy.Authentication` from module code: it is the authentication edge, and an actor it did not seal fails `Scope.actor/1`. A job that acts for a user is enqueued with `Queue.enqueue_for/3` and reads `execution.scope`; it runs only while Core User still proves the user (and any impersonation it was queued under).

## Permission checks after mount

Do not duplicate host session or route checks in page handlers; `BilimbiWeb.RouteAccess` owns that boundary, including Base UI component events. For additional operation capabilities, use `Bilimbi.Base.Authz.LiveAuthorization.authorize_event/2`; its moduledoc owns the contract and refusal handling. Cached `can_*?` assigns are presentation state, not authority. See [Live navigation](web/docs/navigation.md) for host behavior.

## Tests

Assert what the running system does. Do not add a test that reads or pattern-matches a source file to prove a bug is gone: two did that and passed while the problem they claimed to catch was still in the tree. A security or database boundary is proved by making PostgreSQL refuse; `apps/base/database/AGENTS.md` names the control.

`insert_tenant!/1` creates the platform operator by default; pass `is_platform_operator: false` for any other tenant. See `Bilimbi.Base.Tenancy.TestFixtures.insert_tenant!/1`.

For source guard scans and container checks, use `Bilimbi.Base.ModuleRegistry.MixDiscovery`'s validated module and container paths. A fixed `apps/*/*` glob misses mounted Domain and Extension packages. See `module_source_files/2`, `module_route_files/1`, and `container_paths/1` in `apps/base/module_registry/mix/module_discovery.exs`.

A test that runs host tasks such as `bilimbi.migrate` from the umbrella root takes its expected migrations from the root runtime, not from `Compatibility.migration_entries()` in the package VM. The package loads only its own closure, so a mounted Domain's migrations are missing there and the expectations stop matching. `workspace_migration_entries/1` in `apps/core/compatibility/test/platform_baseline_e2e_test.exs` and `MountedDomainFixture` in that package's `test/support/` show the pattern.

## Routes

Let `BilimbiWeb.RouteOverlap` check the compiled router for route conflicts. A route manifest alone misses direct host routes; injected routes carry their descriptor owner and layer in Phoenix route metadata. See `apps/web/lib/bilimbi_web/discovered_routes.ex`.

## Composition lock

Use `Bilimbi.CompositionLock.lockfile!/1` from `mix/composition_lock.exs` for every Mix project. A mounted optional repository resolves into the composition overlay; a literal root `mix.lock` path lets `deps.get` or `deps.unlock --unused` rewrite the Platform's tracked lock. The publish and pinned CI sequence is in `docs/architecture/0010_composition-model.md`.

## Maintaining this file

Keep this note short. Point at the component, its comment, or DESIGN.md; do not copy them.
