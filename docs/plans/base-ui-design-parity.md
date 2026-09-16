# Base UI Design Parity

**Status:** In progress — application shell, impersonation audit actor and the named icon vocabulary are merged to `main`; Design Library specimen separation, state coverage, drift guards and live timestamp display are implemented and in review
**Last Updated:** 2026-09-15
**Sources:** `docs/plans/base-ui-design-library.md`; `DESIGN.md`; root `AGENTS.md`; Issue #691; https://github.com/BelimbingApp/bilimbi/pull/696 (merged); [campaign #709](https://github.com/BelimbingApp/bilimbi/issues/709); [shell #710](https://github.com/BelimbingApp/bilimbi/issues/710) (closed by #711); [audit actor #712](https://github.com/BelimbingApp/bilimbi/issues/712) (closed by #714); [icon registry #713](https://github.com/BelimbingApp/bilimbi/issues/713) (closed by #715); [drift guards #718](https://github.com/BelimbingApp/bilimbi/issues/718); [specimen separation #719](https://github.com/BelimbingApp/bilimbi/issues/719); [state coverage #720](https://github.com/BelimbingApp/bilimbi/issues/720); [display controls #721](https://github.com/BelimbingApp/bilimbi/issues/721); `apps/base/ui/`; `apps/web/assets/css/app.css`; Belimbing `UiReferenceSection`, UI Reference partials, shared UI components, `tokens.css`, and `components.css`
**Agents:** `crewmate/gpt-6` (`agent:kiatng-sol-medium`); `astra_pr_gate/gpt-6-astra` (autonomous design steward); `claude-fable-audit-1/claude-fable-5-1`; `codex-terra-icons-1/gpt-5.6-terra`; `claude-fable-guards-1/claude-fable-5-1`; `codex-sol-specimens-1/gpt-5.6-sol`; `codex-luna-states-1/gpt-5.6-luna`; `claude-opus-datetime-1/claude-opus-5`

## Problem Essence

Bilimbi has a recognisable identity, but its shared UI has less breadth and less complete interaction behaviour than Belimbing. Copying Belimbing wholesale would erase Bilimbi's brand and import Laravel-shaped implementation, while improving one screen at a time would reproduce the drift the Design Library is meant to stop.

## Desired Outcome

Bilimbi reaches parity with the useful user-visible capabilities and interaction quality of Belimbing while remaining unmistakably Bilimbi. Parity means equivalent purpose, states, keyboard behavior, responsive behavior, feedback, recovery and production usefulness; it does not mean matching Blade components, CSS values, route names or pixels.

The Design Library is the visual and interaction review surface for this work. Astra compares each catalog item against the live Belimbing reference, records its disposition, implements it through shared Base UI where appropriate, exercises it in the live library, and verifies adoption by at least one real screen before calling it complete. The user has delegated routine design judgment and does not need to approve each component or family.

The campaign is structured so audits and production adoption can run in parallel without several agents redefining the same shared primitive at once.

## Current Baseline

The foundation at https://github.com/BelimbingApp/bilimbi/pull/696 merged on 2026-09-14 at 07:02:16 UTC with all seven checks passing. It integrates `main` through `d93feb1`, including #694's status-first company actions and 24px icon hit targets. Its accepted decisions retain compact `rounded-md` fields, brand focus, open filter toolbars and calm destructive actions. Inline icon controls retain their small glyphs within 24px targets; table and toolbar controls remain 28px. Pagination uses content-sized `w-auto`, `h-7`, `pl-2 pr-6` geometry so three-digit options clear the dropdown arrow, preserving the intentional #304 correction in both root guidance and `DESIGN.md`.

The foundation completed specimen interactions, browser review and `mix precommit`; its closeout evidence is recorded in the Design Library plan. The account menu, top-bar utilities, icon parity and wider catalog are subsequent implementation slices; their recorded design contract does not claim they already ship. No agent should treat accidental branch state, a Belimbing value or an isolated production screen as design authority.

## Top-Level Components

### Bilimbi Identity Baseline

The identity baseline records the characteristics that parity work must preserve. These are platform-level constraints, not decisions that each component agent can reopen independently.

| ID | Identity to keep | Contract |
|---|---|---|
| K01 | Warm semantic colour system | Keep the warm neutral canvas, olive action colour, lime orientation accent and separate success, warning and danger roles. |
| K02 | Bilimbi geometry | Keep `rounded-xl` primary surfaces, compact `rounded-md` fields and table controls, the accepted action hierarchy, and hairline ledger structure. |
| K03 | Compact operational density | Preserve fast scanning, dense tables, compact controls and restrained spacing without becoming cramped. |
| K04 | Instrument Sans hierarchy | Preserve the current typeface, compact navigation scale and tabular numerals for comparable data. |
| K05 | Brand means orientation | Lime identifies selection, focus, active navigation and location; it never represents status. |
| K06 | Calm action language | Keep the deep-olive primary action, scarce emphasis and calm treatment of destructive work. |
| K07 | Bilimbi mark and wordmark | Keep the product mark, wordmark and local graphic identity. |
| K08 | Ledger page archetypes | Keep one shared width and hierarchy for list, form and detail pages. |
| K09 | Trustworthy behavior and voice | Feedback is truthful, accessible and recoverable; copy remains plain, calm and operational. |

### Parity Capability Catalog

The catalog is organized by what a human is trying to review, not by Laravel or Phoenix implementation. The assessment is a starting point to verify in the live products; it is not an automatic decision to port every Belimbing component.

| ID | Design element | Bilimbi now | Parity target |
|---|---|---|---|
| FND-01 | Semantic colours | Strong identity and semantic roles | Keep Bilimbi; verify light/dark contrast and role separation. |
| FND-02 | Typography hierarchy | Present | Keep Bilimbi; verify headings, body, labels, help and tabular data. |
| FND-03 | Spacing and density rhythm | Partly standardized | Define one compact rhythm across primitives and page assemblies. |
| FND-04 | Shape, lines and elevation | Strong identity with local drift | Keep Bilimbi geometry; remove unexplained variations. |
| FND-05 | Focus, motion and reduced motion | Partial | Define consistent focus visibility, transition purpose and reduced-motion behavior. |
| FND-06 | Icon language and catalog | Registry exists; review is limited | Use Belimbing's established icon choices for equivalent actions, except logout, while rendering them through Bilimbi's icon component and registry. Add searchable visual review, empty result, copy and copied feedback. |
| LAY-01 | Authentication shell | Exists | Compare first impression, responsive behavior, errors and recovery. |
| LAY-02 | Application shell and account footer | Exists | Remove persistent company and tenant repetition. Put the current timezone and light/dark theme selectors in the top bar. Keep the user circle at the bottom left as the account and scope entry point; show an always-visible warning only for unusual or safety-critical scope. Match the best collapse, drawer and navigation-continuity behavior. |
| LAY-03 | Page width and page header | Shared primitives exist | Cover title, subtitle, action, pin, contextual help and narrow states. |
| LAY-04 | Secondary side panel | Bespoke Design Library example | Establish one responsive page-local navigation pattern with desktop rail and mobile access. |
| LAY-05 | Index, form and detail geometry | Partial conventions | Define complete assemblies rather than leaving every screen to compose them differently. |
| NAV-01 | Main menu tree | Exists | Verify active ancestry, pinned items, reorder, collapse, mobile drawer and persistence. |
| NAV-02 | Tabs | Shared `<.tabs>` used by Schedule and Settings | Provide shared semantics, keyboard navigation, active state and URL/history rules. |
| NAV-03 | Link dictionary and related-link groups | No shared contract | Adopt internal, anchor, external, new-tab and download behavior; mutations remain buttons. |
| NAV-04 | Pagination | Shared component exists | Compare narrow layout, disabled states, page-size control, URL state and accessible labels. |
| NAV-05 | User account and scope menu | Partial user footer exists | On user-circle activation, show signed-in name and identifier, current company and tenant, change password and sign out. Show scope switching only when more than one permitted scope exists. |
| ACT-01 | Buttons | Primary, secondary and destructive basics | Cover emphasis, compact size, disabled, loading, navigation and truthful completion. |
| ACT-02 | Icon actions and groups | Basic icon button exists | Add grouping, context sizing, disabled/loading behavior and accessible tooltips. |
| ACT-03 | Destructive entry and acknowledgement | Inconsistent screen patterns | Standardize consequence copy, confirmation and typed acknowledgement where risk requires it. |
| INP-01 | Shared field shell | Generic input has labels, hints and errors | Standardize required, help, error, disabled, read-only, prefix and suffix placement. |
| INP-02 | Text, email, URL, telephone, number and textarea | Available through the generic input | Complete state and sizing contracts and validate realistic long content. |
| INP-03 | Search | Generic search type | Add clear, empty, loading and result-update behavior. |
| INP-04 | Select, multi-select, checkbox and radio | Shared components for all four, including `<.radio_group>`; state coverage partial | Complete open/close, summary, no-options, outside-click, Escape and keyboard behavior. |
| INP-05 | Date, time, datetime and integer entry | Mostly native generic inputs | Define tabular display, step controls, validation and locale/timezone behavior. |
| INP-06 | Secret input | Password field only | Distinguish saved mask, reveal, replacement and explicit clearing. |
| INP-07 | Searchable and editable combobox | Missing | Adopt the useful Belimbing behavior with full keyboard, async, no-result and commit/cancel states. |
| INP-08 | Country and currency lookup | Missing | Build only the generic visual/interaction seam; domain data stays with its owning module. |
| INP-09 | Segmented control | Missing | Add for short peer choices when a real Bilimbi workflow needs it. |
| INT-01 | Inline text editing | Shared primitive exists | Complete F2/typing entry, Enter/blur save, Escape cancel, focus restore and error recovery. |
| INT-02 | Inline select, combobox and textarea editing | Missing | Add after their underlying controls are accepted. |
| INT-03 | Grouped fact editing | Missing | Support Apply/Cancel where facts must change atomically. |
| INT-04 | Disclosure | No shared primitive | Define open/closed semantics, `aria-expanded`, keyboard behavior and reduced motion. |
| INT-05 | Filter and period patterns | Repeated local compositions | Standardize the shared composition while keeping URL state and production meaning. |
| INT-06 | Unsaved-change and template selection flows | Missing | Defer until a real Bilimbi workflow proves the need. |
| FBK-01 | Inline alerts | Shared primitive exists | Verify status semantics, copy, contrast, icons and dismissibility. |
| FBK-02 | Flash and notification behavior | Basic fixed flash | Define stacking, timing, sticky warning/error, manual dismissal and redirect continuity. |
| FBK-03 | Validation, disabled and loading states | Partial | Make the states visibly distinct and prevent duplicate work. |
| FBK-04 | Empty, permission, unavailable, error and recovery states | Library specimens exist | Establish reusable page and region patterns with truthful recovery. |
| OVR-01 | Standard modal | Missing | Add accessible open, close, Escape, backdrop, focus containment and focus return. |
| OVR-02 | Confirmation modal | Missing | Add consequence-first confirmation without copying Belimbing's accessibility gaps. |
| OVR-03 | Inspector drawer | Missing | Add only for a real inspector workflow; cover mobile width, resizing and remembered width. |
| OVR-04 | Tooltip and popover behavior | No shared contract | Define only where labels or contextual actions genuinely require it. |
| DAT-01 | Cards, facts and dense summaries | Card and ad hoc facts exist | Standardize metadata hierarchy and compact summary composition. |
| DAT-02 | Badges and status treatments | Basic badge exists | Complete neutral, information and status roles without using brand as status. |
| DAT-03 | Tables and sortable headings | Shared table exists | Cover caption, overflow, sticky header, hover, stripes, empty state, footer and truthful sorting. |
| DAT-04 | Absolute and relative time | Absolute datetime exists | Add relative time only with the absolute value available. |
| DAT-05 | Statistics and stat strips | Missing | Add when a dashboard or operational summary supplies a real use case. |
| DAT-06 | Record history, timeline and comparisons | Local or missing | Keep specialist behavior with the owning workflow; share only the generic presentation seam. |
| CMP-01 | Operational index page | Partial specimen | Standardize header, filters, table, actions, empty/loading/error and pagination as one flow. |
| CMP-02 | Form page | Partial specimen | Standardize field rhythm, validation, save/cancel, loading, success and unsaved navigation. |
| CMP-03 | Detail and settings page | Partial conventions | Standardize facts, inline/grouped editing, related navigation and permission states. |
| CMP-04 | Destructive workflow | No complete specimen | Show entry, consequence, acknowledgement, in-flight, success, failure and recovery together. |
| CMP-05 | Authentication and first arrival | Implemented but not parity-audited | Treat login, recovery and dashboard arrival as first-impression acceptance surfaces. |
| CMP-06 | Responsive and theme coverage | Ad hoc | Review representative assemblies at desktop/narrow widths and in light/dark themes. |
| GFX-01 | Mark and wordmark | Present | Keep Bilimbi identity and verify size, surface and contrast uses. |
| GFX-02 | Product and interface icons | Registry and Heroicons exist | Make the approved FND-06 icon set searchable and verify size, alignment and meaning without copying Belimbing assets or framework markup. |
| GFX-03 | Placeholder and empty-state graphics | Limited | Add only when graphics improve comprehension rather than decorate empty space. |

### Disposition Ledger

Every catalog item receives one disposition after visual and interaction review:

- **Keep Bilimbi** — Bilimbi is already the better result; document and enforce it.
- **Equivalent** — capability and quality already match; fill only missing evidence.
- **Adopt adapted** — take Belimbing's useful behavior but render it through Bilimbi identity.
- **Steward review** — Astra compares live alternatives, chooses the best supported treatment within K01–K09 and records the reason; this is temporary audit work, not a user approval queue.
- **Not applicable** — the capability has no honest Bilimbi use; record why and do not build it.

The ledger is campaign tracking, not a permanent second design source. Accepted outcomes move to the live Design Library, Design Spec and shared implementation under the same catalog ID.

#### Recorded dispositions (Phase 0, 2026-09-16)

All 57 rows verified against both live products. Bilimbi was read at `ff5a5a0` on a
private instance; Belimbing at `local.blb.lara`. Each row's full evidence, with the
verification method stated per finding, is in the Phase 0 lane reports.

A disposition here is a starting position with evidence behind it, not an approval to
build. Where the evidence contradicted the catalog's own target, the row says so
rather than being quietly reconciled.

| ID | Disposition | Depends on |
|---|---|---|
| FND-01 Semantic colours | Keep Bilimbi | none |
| FND-02 Typography | Keep Bilimbi | none |
| FND-03 Spacing rhythm | Adopt adapted — named spacing roles, Bilimbi values | before LAY-05, CMP-01…03 |
| FND-04 Shape and elevation | Keep Bilimbi | none |
| FND-05 Focus and motion | Adopt adapted — one focus contract, per-transition `motion-reduce` | before ACT-01, INP-01 |
| FND-06 Icon language | Adopt adapted — searchable catalog; finish the migration | #719 |
| LAY-01 Authentication shell | Keep Bilimbi | none |
| LAY-02 Application shell | Adopt adapted — shipped in #711, confirmed live | none |
| LAY-03 Page header | Adopt adapted — responsive stacking, pin slot, help slot | NAV-01 pin decision |
| LAY-04 Side panel | Adopt adapted | LAY-02 drawer mechanics, #719 |
| LAY-05 Page geometry | Keep Bilimbi | FND-03, LAY-03 |
| NAV-01 Menu tree and pins | **Steward review** — two pin models, one dead | none |
| NAV-02 Tabs | Adopt adapted — ARIA tablist, arrow keys, one URL rule | none |
| NAV-03 Links | Adopt adapted | none |
| NAV-04 Pagination | Keep Bilimbi | none |
| NAV-05 Account menu | Adopt adapted — shipped in #711, confirmed live | multi-scope selector deferred (business decision) |
| ACT-01 Buttons | Adopt adapted | none |
| ACT-02 Icon actions | Keep Bilimbi | ACT-01 loading contract |
| ACT-03 Destructive entry | Adopt adapted | OVR-02, ACT-01 |
| FBK-01 Inline alerts | Adopt adapted | none |
| FBK-02 Flash | Adopt adapted | z-order agreed with OVR-01 |
| FBK-03 Validation, disabled, loading | Adopt adapted | ACT-01 |
| FBK-04 Empty, permission, error, recovery | Keep Bilimbi | none |
| OVR-01 Standard modal | Adopt adapted — share the shell drawer's containment, do not re-add | extract containment hook from `app_shell.js` |
| OVR-02 Confirmation modal | Adopt adapted | OVR-01, ACT-03 |
| OVR-03 Inspector drawer | Not applicable — no workflow needs it | a real inspector workflow |
| OVR-04 Tooltip and popover | Equivalent | none |
| INP-01 Field shell | Adopt adapted — required marker, prefix/suffix, read-only | none — foundation |
| INP-02 Text and textarea | Keep Bilimbi | INP-01 |
| INP-03 Search | Adopt adapted — narrowed to the magnifier only | INP-01; clear → INT-05 |
| INP-04 Choice controls | Adopt adapted (multi-select) / Keep Bilimbi (radio group) | INP-01 |
| INP-05 Date, time, integer | Adopt adapted — narrow, `tabular-nums` | INP-01 |
| INP-06 Secret | Adopt adapted — excluding reveal-a-saved-secret | INP-01 |
| INP-07 Combobox | Adopt adapted | INP-01, INP-04 |
| INP-08 Country and currency | Adopt adapted — seam only | INP-07 |
| INP-09 Segmented control | Adopt adapted | INP-01, FND-05 |
| INT-01 Inline text edit | Adopt adapted | INP-01 |
| INT-02 Inline select and combobox | Adopt adapted | INT-01, INP-04, INP-07 |
| INT-03 Grouped fact editing | **Equivalent** — already in ten production LiveViews | INP-01, ACT-01 |
| INT-04 Disclosure | Adopt adapted — as two distinct things | INP-04, FND-05 |
| INT-05 Filter and period | Adopt adapted | INP-01, INP-03, OVR-01 |
| INT-06 Unsaved change | Not applicable — keep deferred | none |
| DAT-01 Record fact list | Keep Bilimbi — Belimbing hand-writes `<dl>` too | none for the API; migration is Phase 5 |
| DAT-02 Status and badges | Adopt adapted — `info` role only, never `accent` | a new `info` role in `@theme` (FND) |
| DAT-03 Tables | Keep Bilimbi (density, header case, sort) + Adopt adapted (accessible name, `title`) | shared-component edit; raw tables are Phase 5 |
| DAT-04 Timestamps | Keep Bilimbi (absolute) + Adopt adapted (relative) | none for the primitive; raw-format sites are Phase 5 |
| DAT-05 Stat cards | Adopt adapted — now, not later; already shipping | label/value scale should become shared tokens |
| DAT-06 Record history | Keep Bilimbi — ownership split is strictly better | `history` icon name depends on GFX-02 |
| CMP-01 Operational index | Keep Bilimbi on URL state and page sizes | settle one URL vocabulary before Phase 5 |
| CMP-02 Create and edit form | Keep Bilimbi | `aria-describedby` belongs to INP-01 |
| CMP-03 Detail page | **Steward review** | DAT-01 |
| CMP-04 Destructive flow | Adopt adapted — take the acknowledge-input contract | OVR-01, OVR-02 |
| CMP-05 Authentication pages | Equivalent | none |
| CMP-06 Page header assembly | Adopt adapted — responsive stacking | none; integration owner, not Phase 5 |
| GFX-01 Identity mark | Keep Bilimbi | none |
| GFX-02 Icon assets | Adopt adapted — but reorder: register the missing names first | none for the registration fix |
| GFX-03 Illustration | Not applicable | none |

##### Targets the evidence contradicts

These are recorded rather than reconciled, because the catalog was written before the
products were read and the plan forbids treating existence as acceptance.

- **CMP-01** — moving toward Belimbing would be a regression. Belimbing keeps only
  `page` in the URL and offers 10/20/50/100 page sizes; Bilimbi already mandates
  25/50/100/300 with full URL state.
- **DAT-05** — "Missing" is wrong. Five stat cards ship on `/dashboard`, duplicated
  into ten markup blocks with 65 arbitrary-value classes.
- **DAT-04** — relative time already ships in notifications, in a bare `<span>` with
  no `<time>`, no `datetime` and no `title`, frozen at render.
- **INT-03** — "Missing" is wrong. Bilimbi runs it in ten production LiveViews and
  Belimbing has no component either.
- **INP-03** — Belimbing *removes* the native clear affordance Bilimbi keeps; there is
  nothing to adopt.
- **OVR-01** — "Missing" understates. The shell drawer already implements `inert`,
  `aria-modal` and backdrop mechanics; the work is to share it, not to build it.
- **LAY-02, NAV-05** — the "Bilimbi now" cells describe pre-#711 state; both shipped.
- **INT-04** — reduced motion is not adoptable; neither product has a contract.

##### Defects found while verifying

Not catalog work. These are user-facing faults in shipped code, listed so they are not
lost inside a design ledger:

- Three destructive controls fire with no confirmation at all — `remove_role`
  (`core/user/.../show_live.ex:1109`), `remove_capability` (`:1260`) and
  `remove_activity` (`core/company/.../show_live.ex:982`). Two of those revoke
  authorization. 22 `data-confirm` attributes exist elsewhere, so the convention is
  established and these are the exceptions.
- `<.multi_select>` cannot be closed by Escape or by its own toggle, and its
  `aria-expanded` is the literal `"false"` at `components.ex:669` — it never changes,
  so assistive technology is told the panel is shut while it is open.
- `<.inline_edit>` drops focus to `document.body` on every Enter-commit; Escape
  returns focus correctly. A blank commit is silently discarded under a stale success
  flash.
- Four icon names — `bilimbi-plus`, `bilimbi-pencil`, `bilimbi-link-slash`,
  `bilimbi-x-mark` — are unregistered across 11 call sites, so "add", "edit", "unlink"
  and "remove" all render the registry's fallback glyph.
- Per-user pins are built twice and shipped once: `PinController`,
  `/api/pins/toggle|reorder`, `User.toggle_user_pin/reorder_user_pins` and the
  `user_pins` table exist, and `app_shell.js` calls that API zero times while using
  `localStorage` ten times. Pins do not follow the account.
- `<.header>` never stacks; its actions are clipped and unreachable at 420px, where
  Belimbing's header wraps.
- `:info` flashes render with success (green) roles.

##### Corrections to this document

- Line 339 claims 73 glyph entries; `IconRegistry` holds 3 glyphs, 9 shell names and
  49 actions, with 44 raw `hero-*` strings still outside it.
- `app.css:222` says menu typography matches Belimbing. Belimbing renders 14px/400;
  Bilimbi renders 13px/350.
- The Design Library labels the sign-in mark 48px; production renders 36px.
- The raw-palette guard in root `AGENTS.md` §12 greps `apps/*/lib`, which matches only
  `apps/web/lib`. The 24 module libraries — including `apps/base/ui/lib`, where the
  shared components live — sit one level deeper and are not scanned. Both globs
  currently return 0, so nothing is wrong today; the guard simply would not catch it.

##### What Phase 0 did not verify

Stated so later phases do not mistake silence for coverage: keyboard focus-visible
rendering in either product (the browser bridge could not deliver trusted key input),
contrast ratios beyond Bilimbi's automated test, any flow requiring writes
(password reset, Belimbing `wire:loading`), Belimbing modal focus behaviour beyond
dispatched events, and dark theme on the Lane B rows.

### Live Review Surface

The Design Library uses one shared secondary catalog and one review surface per family. It renders the real Bilimbi implementation in meaningful states. Comparison notes describe user-visible Belimbing behavior and recognizable product use cases; normal UI does not expose agent instructions, repository ownership or Laravel component names.

To make parallel work mergeable, family specimens may be separated into family-owned view files behind the existing Design Library shell. Do not split the production component API merely to create artificial agent concurrency.

### Shared Base UI and Production Adoption

Base UI owns generic presentation and interaction contracts. Domain-coupled data and workflows remain with their module: country/currency data, record history, business status transitions and destructive authorization do not move into Base UI merely because their controls share a visual pattern.

A parity component is incomplete until at least one real Bilimbi screen uses it. Production rollout happens by module after the shared contract and Design Library specimen are accepted.

## Design Decisions

### Parity is behavioral, not a pixel clone

A pixel clone would erase Bilimbi identity and copy weaknesses. A component-count checklist would reward unused controls. The recommended direction is capability and behavioral parity: match or exceed the useful task, states, accessibility and recovery while preserving Bilimbi's identity baseline.

### The catalog is a migration ledger, not another SSOT

A text-only inventory is easy for agents but impossible to validate visually. A permanent runtime registry adds machinery without improving the design. The recommended direction is a temporary plan ledger for coordination, with real specimens and accepted results living in the Design Library, Design Spec and production components.

### Parallelize evidence and adoption; serialize shared authority

One serial agent would be slow, while several agents concurrently changing theme and shared component files would recreate drift through merge conflict. The recommended direction is staged parallelism: audit families concurrently, use one integration owner for shared Base UI and design authority, then migrate independent module screens concurrently after each shared contract stabilizes.

### Astra owns routine design acceptance

Component-by-component human selection would interrupt the authorized campaign. An unrestricted whole-library rewrite would hide accumulated decisions and weaken verification. The accepted direction is autonomous Astra stewardship in complete, bounded slices: inspect Belimbing visually and in source, implement through Bilimbi's shared foundations, verify the live specimen and a production workflow, then record evidence before proceeding. User review remains available without being a dependency.

Preserve K01–K09 and the user's explicit shell and icon requirements. Escalate only when the work requires a new business, security or durable data-contract decision outside the accepted scope. Routine geometry, interaction, icon mapping, responsive layout and accessibility judgments belong to Astra. Shared-file ownership remains singular; delegated evidence and module adoption may proceed in parallel.

The first parity slice owns `LAY-02`, `NAV-05`, shell-related `FND-06`, timezone/theme utilities and desktop, collapsed-sidebar and narrow-drawer states. Subsequent slices follow dependency order rather than waiting for every family audit to finish.

### Account and tenancy context are disclosed when useful

Keeping company and tenant in the top strip makes known context compete with the current task. Hiding scope everywhere is also unsafe for platform operators, impersonation and cross-company work. The recommended direction is progressive disclosure: the bottom-left user circle opens one account menu containing identity, company, tenant and account actions. A switcher appears only for users who can switch. Unusual or safety-critical scope remains visible outside the menu as a persistent warning.

## Public Contract

- Belimbing is reference evidence, not visual or implementation authority.
- Bilimbi identity IDs `K01`–`K09` are fixed constraints for parity work; Astra resolves routine design choices within them.
- Ordinary company and tenant context is available through the bottom-left user account menu, not repeated in the top strip. Platform-operator, impersonated and other safety-critical scope remains visibly disclosed while active.
- The top bar exposes the current timezone and light/dark theme selectors. What a selection must do — apply immediately, persist for the signed-in user and render truthfully — is stated once in `DESIGN.md`'s application shell section.
- Equivalent actions use Belimbing's established icon choices through Bilimbi's icon registry, with logout as the explicit exception.
- Every parity issue names the catalog IDs it owns, its dependencies, affected routes, owned files and acceptance evidence.
- A catalog item is complete only when its disposition is recorded, the real component is shown in the Design Library, applicable states and keyboard behavior are tested, narrow and theme behavior are reviewed, and one production screen adopts it.
- Astra accepts routine design choices from visual, interaction and production evidence; component and family completion does not require human selection. Unresolved business, security or durable data-contract decisions remain explicit blockers for the affected work only.
- Shared Base UI, theme, Design Spec and the parity ledger have one integration owner at a time.
- Audit agents and module rollout agents do not edit those shared authority files concurrently.
- Feature modules use semantic Base UI contracts and do not import Belimbing assets, CSS, Laravel names or private design-library markup.
- Specialist controls are built only for a real Bilimbi workflow; parity is not permission for speculative inventory growth.
- Bilimbi may exceed Belimbing where accessibility, failure handling or interaction integrity is incomplete.

## Phases

### Phase 0 — Align the baseline

Goal: Establish one current identity and catalog before any parity implementation.

- [x] Bring the branch onto the current `main` history at merge commit `3a4d918`. `{agent:kiatng-sol-medium}`
- [x] Integrate `main` through `d105ebe` without rewriting branch history, at `3840987`. `{astra_pr_gate/gpt-6-astra}`
- [x] Preserve the subsequently merged #694 behavior through shared 24px inline icon controls, 24px sidebar unpin controls, status-first company actions and the pin-state regression test. `{astra_pr_gate/gpt-6-astra}`
- [x] Reconcile current guidance on compact fields, open filter framing, calm destructive actions and content-sized pagination; distinguish planned shell contracts from shipped behavior. `{astra_pr_gate/gpt-6-astra}`
- [x] Preserve identity IDs `K01`–`K09` and delegate routine acceptance to Astra under the user's instruction. `{astra_pr_gate/gpt-6-astra}`
- [x] Verify every catalog row against the current Bilimbi build and Belimbing reference. `{claude-opus-datetime-1/claude-opus-5}`
- [x] Give each row its initial disposition and dependency without treating component existence as acceptance. `{claude-opus-datetime-1/claude-opus-5}`
- [x] Create campaign #709 and shell child #710; create subsequent children when their slice boundaries are verified. `{crewmate/gpt-6}`

Validation: A new agent can tell what must remain Bilimbi, what is being compared, what is already equivalent, what Astra decides and which business/security/data-contract questions require escalation.

### Phase 1 — Make the Design Library the parity workbench

Goal: Let Astra or a product reviewer inspect one family at a time without a long, conflicting page.

- [ ] Align the secondary menu with the catalog families: Foundations, Page Structure, Navigation and Links, Actions, Inputs, Interaction Patterns, Feedback and States, Overlays, Data Display, Composite Patterns and Graphics.
- [ ] Separate family specimens into mergeable family-owned view boundaries while retaining one Design Library shell and production component source.
- [ ] Show the current Bilimbi component in every meaningful state for the active family.
- [ ] Present alternatives under steward review together with recognizable use cases and stable catalog IDs; record Astra's accepted disposition and rationale.
- [ ] Add focused coverage for variants, states and interactions; component-name presence alone is not enough.

Affected pages: `/system/design-library`, `/system/design-library/components`, `/system/design-library/graphic`, `/system/design-library/design-spec`

Validation: The reviewer can reach any catalog family quickly, interact with the real component and record a decision by stable ID.

### Phase 2 — Parallel family audits

Goal: Complete evidence and recommended dispositions without changing production design prematurely.

- [ ] Lane A — audit FND, LAY and NAV against both applications and representative shell/page routes.
- [ ] Lane B — audit ACT, FBK and OVR, including loading, dismissal, confirmation and recovery.
- [ ] Lane C — audit INP and INT, including field shell, keyboard behavior, editing and rich choices.
- [ ] Lane D — audit DAT, CMP and GFX, including actual index, form, detail, authentication and dashboard flows.
- [ ] Integration owner consolidates reports into this ledger and removes duplicate or speculative targets.

Validation: Every catalog item has evidence, a recommended disposition, dependencies and at least one real Bilimbi use case or a reason to omit it.

### Phase 3 — Shared parity foundations

Goal: Build accepted shared contracts in dependency order.

- [ ] Stabilize identity tokens, focus, field shell, card, icon and action foundations.
- [ ] Implement accepted navigation, link and action contracts.
- [ ] Implement accepted native input, choice, feedback and data-display contracts.
- [ ] Implement accepted combobox, edit-in-place, disclosure, modal and confirmation contracts only after their foundations are stable.
- [ ] Add each real component and its state/interaction evidence to the Design Library in the same change.
- [ ] Keep shared edits under one integration owner; parallel agents prepare independent evidence, tests and module-local adoption work.

Validation: Each accepted shared primitive has an intentional API, live specimen, interaction tests and no unexplained local palette or geometry override.

### Phase 4 — Canary assemblies

Goal: Prove the primitives work together before broad migration.

- [ ] Apply accepted patterns to one real operational index page.
- [ ] Apply accepted patterns to one real create/edit form.
- [ ] Apply accepted patterns to one real detail or settings page.
- [ ] Review all three at desktop and narrow widths, light and dark themes, keyboard only, loading, error and permission states.
- [ ] Correct composition problems in the shared layer before starting broad rollout.

Validation: Astra's browser and interaction review confirms that parity improves real work and still looks and feels like Bilimbi, with recorded evidence for each assembly.

### Phase 5 — Parallel production rollout

Goal: Remove local drift after the shared contracts stabilize.

- [ ] Lane A — Base Authz, Session and Tenancy screens.
- [ ] Lane B — Base Audit, Schedule, Settings, System and Performance screens.
- [ ] Lane C — Core Company, Address and Geonames screens.
- [ ] Lane D — Core Employee, User and User Administration screens.
- [ ] Each lane edits only its owning module and tests; shared Base UI changes return to the integration owner.
- [ ] Each migrated archetype is rechecked in the Design Library and on its production route.

Validation: Production screens use accepted shared patterns, module workflow tests pass, and no lane introduces a new unexplained variant.

### Phase 6 — Parity acceptance and drift prevention

Goal: Close the campaign with evidence that remains useful as Bilimbi evolves.

- [ ] Classify every catalog item as Keep Bilimbi, Equivalent, Adopt adapted or Not applicable; no item remains ambiguous.
- [ ] Verify applicable default, hover, focus, active/open, disabled, loading, validation, error, empty, dark and narrow states.
- [ ] Verify keyboard movement, focus containment/return, screen-reader semantics, duplicate-work rejection and truthful recovery.
- [x] Build the Design Library drift guards at the start of the campaign instead of at closeout, so later slices land against them rather than accumulating drift: `apps/base/ui/test/design_library_imitation_test.exs` rejects anchors that name no shared component, hand-written control markup and undeclared specimen cards; `design_library_coverage_test.exs` requires a `component-<name>` block per component and variation on the states it declares, showing at least two of an axis's declared states where it declares two or more and the single one where it declares one. Both read the template through `Bilimbi.Base.UI.DesignLibrarySource`, which owns the rules and is covered on fixtures by `design_library_rules_test.exs`. Both are tagged `:design_library_drift` and stay out of the default run and `mix precommit` until the specimens they report are corrected; run them with `mix test --include design_library_drift`. `{claude-fable-guards-1/claude-fable-5-1}`
- [ ] Add guards for raw palette use, local component forks, missing Design Library states and unregistered icons where deterministic checks are useful.
- [ ] Run component, LiveView, module workflow, asset and full precommit validation.
- [ ] Record the accepted catalog IDs in Design Spec and close the execution issues with browser evidence.

Validation: Bilimbi matches or exceeds the useful design capability of Belimbing, preserves its own identity, and makes later drift visible before it reaches users.

### Application shell slice — Issue #710

Goal: Make account context accessible without routine top-bar repetition and make display utilities immediately useful on every authenticated screen.

Affected pages: `/dashboard`, `/companies`, all four `/system/design-library` routes, `/settings/password`.

- [x] Verify the merged foundation and create child issue #710 under #709 with the exact campaign label. `{crewmate/gpt-6}`
- [x] Inspect the live starting shells and existing preference and identity contracts. `{crewmate/gpt-6}`
- [x] Implement the shared account menu, safety warning, display utilities and responsive shell. `{crewmate/gpt-6}`
- [x] Demonstrate real shared controls and meaningful states in Design Library and record accepted Design Spec. `{crewmate/gpt-6}`
- [x] Verify production adoption, keyboard, desktop/collapsed/narrow, light/dark, persistence and failure recovery. `{crewmate/gpt-6}`
- [x] Run focused checks and `mix precommit`; record final evidence. `{crewmate/gpt-6}`

Initial evidence: Bilimbi's authenticated dashboard repeats tenant name and ID in the top strip and presents platform-operator access as ordinary text; timezone/theme controls are absent. The footer exposes loose identity and logout. Belimbing's dashboard provides clock, sun, moon and computer-desktop utilities; its top-bar source resolves Company/Local/UTC display modes and per-user theme settings. Its account circle links to profile rather than fulfilling Bilimbi's accepted disclosure contract.

Scope-switching disposition: deferred. Current identity resolves exactly one company through `User.get_user/3` and `UserAuth.current_scope_from/2`, so no scope switching is presented and no permitted-scope list is carried on the scope; no new authorization policy or tenant provisioning belongs to this slice. The captain clarified that whether a user should hold more than one company or tenant is undecided; if a need arises, “just have a selector to switch AFTER login”. This is deferred, not declined: the future selector belongs inside the authenticated account menu, as tracked in #710, and lands with the membership policy that defines a scope choice. Presentation must never infer permission from the existence of other companies.


Accepted dispositions (2026-09-14):

| Item | Disposition | Reason and evidence |
|---|---|---|
| LAY-02 desktop, rail and drawer | Adopt adapted | Retain Bilimbi geometry, mark, semantic surfaces, compact navigation and existing pin/tree state. Adopt useful top-bar utilities and account organization. Desktop collapse preserves the bottom-left circle; the narrow drawer contains focus, makes the workspace inert and restores focus on close. |
| NAV-05 account and scope | Adopt adapted | Belimbing exposes identity/profile and logout in its sidebar footer. Bilimbi's shared disclosure fulfills the accepted name, identifier, company, tenant, password and sign-out contract. Current identity holds exactly one scope, so the menu presents no switching. Multi-company membership policy remains deferred as described above. |
| LAY-02 safety context | Adopt adapted | Routine scope moves into the account menu. Platform-operator and impersonated access remain above the workspace, including when the narrow drawer covers content. Existing warning surface/line/ink roles preserve contrast in both themes. Ordinary scope has no warning; impersonation retains its stop action. |
| Top-bar timezone | Adopt adapted | Belimbing's Company/Local/Stored choices and clock meaning are useful. Bilimbi uses the existing Base DateTime preference contract. A confirmed save patches the shell in place — the control, the per-process display context and the confirmation all update without navigation, so keyboard focus stays on the operated control — and every timestamp `<.datetime>` has already rendered follows it, including rows a LiveView stream handed to the DOM; that last part was deferred in this slice and delivered by the follow-up recorded below. The browser still invents no company or stored-UTC text: the element carries the string the server rendered for each mode and the browser only swaps between them, while `:local`, which the server cannot decide, is formatted in the browser as it always was. Explicit per-element display and calendar dates remain independent. |
| Top-bar theme | Adopt adapted | Preserve Light/Dark/System as three explicit choices. Existing Core User preference storage remains authoritative. System follows browser appearance; failed writes retain the saved choice and provide recovery feedback. |
| FND-06 shell icons | Equivalent | Clock, sun, moon, computer desktop, navigation bars and password key use familiar meanings through `IconRegistry.shell/1`. The existing Bilimbi navigation registry and impersonation icon remain in use. The wider searchable icon catalog is outside this slice. |
| FND-06 logout exception | Keep Bilimbi | Keep the existing rightward sign-out arrow meaning and label it “Sign out”; no Belimbing icon asset is copied. |

Implementation and adoption: `Bilimbi.Base.UI.ShellComponents` supplies the account disclosure, access warning and display controls to `Layouts.app`. The authenticated Web hook resolves fresh session identity before preference writes and uses the existing User and DateTime APIs; no schema or preference-key migration was needed. `Bilimbi.Core.User.DisplayPreferences` owns the account's theme, time display and language: one resolved snapshot and one durable write, used by the shell hook, the `/api/theme` adapter and the appearance screen alike. The impersonation refusal is stated once there, so an impersonated session writes none of them from any of the three surfaces — the appearance form names the fields it refused and leaves the viewed account's rows untouched, and the shell replaces its controls with the active time display and says why. The authenticated scope carries that one snapshot, which stamps the root layout, fills the timestamp display context and renders both the top-bar controls and the appearance form's theme and time-display fields; every confirmed write refreshes it, so no surface keeps a second copy. Every timestamp `<.datetime>` has already rendered follows a saved mode at once, including stream rows the server never re-renders: the element carries the server's own text for both server-decided modes and the `DateTime` hook swaps to the one the shell publishes. An instant given an explicit `display` stays pinned to that context instead. Every authenticated route adopts the shell, with direct browser checks on `/dashboard`, `/companies`, `/settings/password` and all four Design Library routes. `/system/design-library/components#component-shell` demonstrates a live timestamp and points at the page's own top-bar display controls and bottom-left account circle rather than duplicating either. `/system/design-library/design-spec#spec-shell` records the accepted user behavior.

Validation evidence:

- `mix precommit` passed at commit `06fe012` on 2026-09-14 — all Base/Core suites, 547 Web integration tests and six installed contribution snapshots, with `mix format --check-formatted` and `git diff --check` clean. That count was measured at that commit only; later review commits changed shell, `user_auth`, appearance and controller source and rewrote the shell, appearance and controller tests, so the final tree's authoritative result is the one the shipping gate records, not this line. Meaningful coverage includes revoked-session rejection, per-user isolation, remount persistence, invalid input and failed HTTP writes, the impersonation refusal at the shared save boundary, ordinary/operator/impersonated warnings, duplicate-work prevention, disconnect/unknown-result feedback, and the in-place shell patch that follows a saved time display.
- Browser verification of the shipped save interaction was re-performed against the final tree (this branch's head, with the in-place patch and `Bilimbi.Core.User.DisplayPreferences` as the single writer), in an isolated `chrome-devtools-axi` session on an isolated preview: a throwaway database copied from `bilimbi_dev` and a server on port 4021 started from this worktree. Both shared processes (ports 4000 and 4017) and the shared `bilimbi_dev` database were left untouched, and the preview database was dropped afterwards. What was exercised and observed:
  - **Keyboard-only time display.** Focus `#app-display-timezone` → Enter opens the panel and moves focus to the first choice → two Tabs reach “Stored UTC” → Enter. The page did not navigate (`/dashboard`, `#app-shell` still attached), focus returned to `#app-display-timezone`, `#app-preference-feedback` became visible reading “Time display saved.”, the trigger label and `title` became “UTC”, `aria-pressed` moved from `#app-display-company` to `#app-display-utc`, and the panel closed.
  - **Theme.** Dark stamped `<html data-theme="dark">` with the dark canvas and “Theme saved.”; Light stamped `light`; System removed the attribute so `prefers-color-scheme` governs. Focus stayed on the operated icon each time.
  - **Immediate application, and the limit that was closed afterwards.** With a company zone of `Asia/Kuala_Lumpur` stored for the preview company, switching the clock from Stored UTC to Company time changed `#library-shell-time` in place from `14/09/2026, 07:00 UTC` to `14/09/2026, 15:00 +08` — at that commit it was the one specimen handed the tracked snapshot. The sibling `#sample-updated-*` timestamps on the same page, which take no `display`, kept their previous text until the page next rendered, at which point they read `+08`. That partial coverage is exactly what the follow-up recorded below removed, and the specimen now takes no `display` either.
  - **Truthful failure.** A forged unsupported mode pushed through the real control was refused by the server: `#app-preference-feedback` showed “Could not save display preference. Your previous choice is still selected. Try again.” in the danger role, and `#app-display-company` stayed `aria-pressed="true"`.
  - **Two surfaces, one snapshot.** On `/settings/appearance` the time-display select offered exactly Company time / This device's local time / Stored UTC and read `company`. A top-bar save to Stored UTC moved the select to `utc` at once; a following unrelated form change (Dark) left the clock and the select on UTC and applied the theme — the regression that motivated this round.
  - **Account disclosure, persistence, responsive.** The bottom-left circle discloses `Kiat Ng`, the email identifier, Company `Bilimbi Development`, Tenant `Bilimbi local development #1`, Change password and Sign out, with no scope switcher; Escape closes it and returns focus to the circle. No `#app-tenant` repetition in the top bar. Saved theme and mode persisted across navigation. Desktop expanded, the 56px collapsed rail (which keeps the circle and the top-bar controls), and the 390×844 narrow drawer were all exercised; the drawer contains focus and Escape returns focus to `#app-sidebar-toggle`.
- Two client-state corrections landed after that browser pass and are covered by executable tests rather than a repeat browser run: the shell now re-applies its own disclosure state (open panel, `aria-expanded`, the confirmation region) after every server patch, because LiveView re-renders those attributes from static markup; and the focus-restore target is scoped to the panel that actually contains the operated control, so a theme click with the account menu open keeps focus on the theme icon.
- Earlier browser work at `06fe012` compared the reference: Belimbing's timezone menu supports Company/Local/Stored with outside/Escape dismissal, its theme icons are clock/sun/moon/computer-desktop, its timezone save reloads the page, and its failed requests lack the explicit retry feedback implemented here. Reference appearance was changed only in page-local DOM; no reference preference writes were made.
- No extra scopes were provisioned, per the clarified scope decision. Reference source inspected at `06fe012`: `resources/core/views/components/layouts/top-bar.blade.php` and the sidebar components.

Checked visual evidence: [expanded production shell, light](evidence/base-ui-shell/companies-expanded-light.png) and [narrow account drawer, dark](evidence/base-ui-shell/narrow-account-dark-final.png) were captured at `06fe012` and still match the shipped shell; [Design Library, dark](evidence/base-ui-shell/library-shell-dark-final.png) and [Design Library, narrow light](evidence/base-ui-shell/library-narrow-light-final.png) were recaptured against the final tree during the verification above. Screenshots supplement the exercised controls and tests; they are not the interaction evidence by themselves.

Live timestamp display — deferred in this slice, delivered by the follow-up on this branch. A saved time display updated the controls, the per-process display context and any `<.datetime>` handed the tracked snapshot through its `display` attribute, while a timestamp that read the process context implicitly — every other call site — kept its rendered text until its screen next rendered, because LiveView re-renders only dynamics whose own assigns changed and stream-rendered table rows are not re-rendered by any assign change at all. Neither way out considered here was taken: threading `display` through thirty call sites leaves the next one to forget it, and re-rendering the page on save loses the reader's place. Instead `<.datetime>` itself carries the server's text for both server-decided modes and the `DateTime` hook swaps to the one `#app-shell` publishes, so the mechanism lives in the component and no call site opts in. `DESIGN.md`'s “A selection applies immediately” now holds for instants `<.datetime>` has already rendered, not only for subsequent rendering — a screen that formats instants directly is unaffected until it adopts the component — and `#spec-shell` with `apps/base/datetime/docs/README.md` state the delivered behavior. This closes the **datetime live display** task tracked under the campaign umbrella [#709](https://github.com/BelimbingApp/bilimbi/issues/709); like the two client-state corrections above it is covered by executable tests — including one that drives the real hook over the real streamed markup of `/audit/mutations` — rather than by a repeat browser pass.

Audit attribution while impersonating (a preference or mutation recorded the viewed account as actor) was tracked separately and was not changed by this slice; the shell simply refuses the durable display write. That gap is now closed — see the impersonation audit actor slice below.

Delivery: https://github.com/BelimbingApp/bilimbi/pull/711 merged on 2026-09-15, closing #710, after independent review and the no-mistakes shipping gate. Later catalog families, broad production-screen migration, searchable icon parity and drift guards remain open in the campaign phases above.

### Impersonation audit actor slice — Issue #712

Goal: Record the real operator on every action taken while impersonating, so an audit row names who acted rather than who was viewed.

- [x] Establish that impersonated preference and mutation rows recorded the viewed account as actor. `{claude-fable-audit-1/claude-fable-5-1}`
- [x] Record the impersonating operator alongside the impersonated subject on audit rows. `{claude-fable-audit-1/claude-fable-5-1}`
- [x] Cover the attribution with tests and run the shipping gate. `{claude-fable-audit-1/claude-fable-5-1}`

Deferred: no test covers the impersonation label on the audit reader surfaces, so deleting it would not turn the suite red. Tracked as follow-up.

Delivery: https://github.com/BelimbingApp/bilimbi/pull/714 merged on 2026-09-15, closing #712.

### Icon vocabulary slice — Issue #713

Goal: Give familiar actions named entries in the icon registry so call sites name the action rather than a raw `hero-*` string.

- [x] Inventory Belimbing's action icons against Bilimbi's registry; 48 actions mapped, 44 of them gaps. `{codex-terra-icons-1/gpt-5.6-terra}`
- [x] Populate `IconRegistry` with the named action vocabulary, keeping logout as the recorded Bilimbi exception. `{codex-terra-icons-1/gpt-5.6-terra}`
- [x] Run the shipping gate and land the change. `{codex-terra-icons-1/gpt-5.6-terra}`

`IconRegistry` now carries 73 glyph entries and 49 named actions on `main`, against three glyph entries before this slice.

Not delivered by this slice, and still open under FND-06 and GFX-02: the searchable visual icon review with empty-result, copy and copied feedback. The registry holds the vocabulary; no review surface presents it yet.

Deferred: registry names are never proven to resolve — the equality test restates the map rather than rendering each entry. Tracked as follow-up.

Delivery: https://github.com/BelimbingApp/bilimbi/pull/715 merged on 2026-09-15, closing #713.

### In review — not yet merged

These four are implemented with open pull requests. Their catalog rows above stay unticked until they land.

| Issue | Work | PR |
|---|---|---|
| #718 | Design Library drift guards | https://github.com/BelimbingApp/bilimbi/pull/722 |
| #719 | Design Library specimen separation | https://github.com/BelimbingApp/bilimbi/pull/723 |
| #720 | Design Library missing component states | https://github.com/BelimbingApp/bilimbi/pull/716 |
| #721 | Shell display controls with live-following timestamps | https://github.com/BelimbingApp/bilimbi/pull/717 |

The drift guards in #722 land excluded from the default test run and from `mix precommit`, because they report specimens #719 and #720 are still correcting. Moving them into the default run is tracked separately and is blocked on those two. #722 merging does not mean the guards are active.
