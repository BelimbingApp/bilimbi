# Base UI Design Parity

**Status:** In progress — Phase 0 is complete: all 57 catalog rows carry a disposition and dependency in the ledger below, and the Design Library's secondary menu is aligned with the eleven catalog families (#724). Merged to `main` through 2026-09-15: application shell, impersonation audit actor, the named icon vocabulary, Design Library specimen separation, state coverage, drift guards and live timestamp display. Since then the library has been stripped of catalog IDs (#728), and the shared layer has taken much of the accepted action and feedback contract — destructive confirmation (#733), reduced motion with 4.5:1 contrast (#738), stacked flash messages (#741), busy controls and a login screen that reports its progress (#743), the empty and permission region pattern (#740), real dialog semantics on modal overlays (#731), one shared filter toolbar (#745), field shell states (#744), secret reveal and multi-select corrections (#746) and a released shell observer (#747) — alongside icon-name validity (#727, #734), Schedule timestamps and UTC day labels through the datetime component (#735, #737), impersonation reader coverage (#729), corrected catalog rows (#730), drift-guard documentation folded into this plan (#726) and the Belimbing cutover value remap (#725); the drift guards stay excluded from the default run until the four specimen and state failures they report are corrected
**Last Updated:** 2026-09-18
**Sources:** `docs/plans/base-ui-design-library.md`; `DESIGN.md`; root `AGENTS.md`; Issue #691; https://github.com/BelimbingApp/bilimbi/pull/696 (merged); [campaign #709](https://github.com/BelimbingApp/bilimbi/issues/709); [shell #710](https://github.com/BelimbingApp/bilimbi/issues/710) (closed by #711); [audit actor #712](https://github.com/BelimbingApp/bilimbi/issues/712) (closed by #714); [icon registry #713](https://github.com/BelimbingApp/bilimbi/issues/713) (closed by #715); [drift guards #718](https://github.com/BelimbingApp/bilimbi/issues/718) (closed by #722); [specimen separation #719](https://github.com/BelimbingApp/bilimbi/issues/719) (closed by #723); [state coverage #720](https://github.com/BelimbingApp/bilimbi/issues/720) (closed by #716); [display controls #721](https://github.com/BelimbingApp/bilimbi/issues/721) (closed by #717); `apps/base/ui/`; `apps/web/assets/css/app.css`; Belimbing `UiReferenceSection`, UI Reference partials, shared UI components, `tokens.css`, and `components.css`
**Agents:** `crewmate/gpt-6` (`agent:kiatng-sol-medium`); `astra_pr_gate/gpt-6-astra` (autonomous design steward, through 2026-09-15); `claude-fable-steward-1/claude-fable-5-1` (autonomous design steward, from 2026-09-16); `claude-fable-audit-1/claude-fable-5-1`; `codex-terra-icons-1/gpt-5.6-terra`; `claude-fable-guards-1/claude-fable-5-1`; `codex-sol-specimens-1/gpt-5.6-sol`; `codex-luna-states-1/gpt-5.6-luna`; `claude-opus-datetime-1/claude-opus-5`; `claude-opus-families-1/claude-opus-5`; `claude-opus-motion-contrast-1/claude-opus-5`; `fm/modal-a11y-dialog-semantics/opus-5`; `fm/empty-and-permission-states/claude-fable-5-1` (Claude Code running Claude Fable 5.1); `fm/parity-plan-checklist-reconcile/muse-spark` (checklist reconciliation on 2026-09-18, not audit authorship); `fm/icon-registry-name-validity/opus-5`; `crewmate scout` (firstmate scout tasks that record no model — the FND-06 icon inventory and the four Phase 2 lane audits of 2026-09-16; separate sessions from the `crewmate/gpt-6` entry above, which is why these rows carry no model)

## Problem Essence

Bilimbi has a recognisable identity, but its shared UI has less breadth and less complete interaction behaviour than Belimbing. Copying Belimbing wholesale would erase Bilimbi's brand and import Laravel-shaped implementation, while improving one screen at a time would reproduce the drift the Design Library is meant to stop.

## Desired Outcome

Bilimbi reaches parity with the useful user-visible capabilities and interaction quality of Belimbing while remaining unmistakably Bilimbi. Parity means equivalent purpose, states, keyboard behavior, responsive behavior, feedback, recovery and production usefulness; it does not mean matching Blade components, CSS values, route names or pixels.

The Design Library is the visual and interaction review surface for this work. The design steward compares each catalog item against the live Belimbing reference, records its disposition, implements it through shared Base UI where appropriate, exercises it in the live library, and verifies adoption by at least one real screen before calling it complete. The user has delegated routine design judgment and does not need to approve each component or family.

The campaign is structured so audits and production adoption can run in parallel without several agents redefining the same shared primitive at once.

## Current Baseline

The foundation at https://github.com/BelimbingApp/bilimbi/pull/696 merged on 2026-09-14 at 07:02:16 UTC with all seven checks passing. It integrates `main` through `d93feb1`, including #694's status-first company actions and 24px icon hit targets. Its accepted decisions retain compact `rounded-md` fields, brand focus, open filter toolbars and calm destructive actions. Inline icon controls retain their small glyphs within 24px targets; table and toolbar controls remain 28px. Pagination uses content-sized `w-auto`, `h-7`, `pl-2 pr-6` geometry so three-digit options clear the dropdown arrow, preserving the intentional #304 correction in both root guidance and `DESIGN.md`.

The foundation completed specimen interactions, browser review and `mix precommit`; its closeout evidence is recorded in the Design Library plan. The account menu and top-bar utilities shipped in the application shell slice (#711) and the named icon vocabulary in #715; the searchable icon review and the wider catalog are subsequent slices whose recorded design contract does not claim they already ship. No agent should treat accidental branch state, a Belimbing value or an isolated production screen as design authority.

## Top-Level Components

### Bilimbi Identity Baseline

The identity baseline records the characteristics that parity work must preserve. These are platform-level constraints, not decisions that each component agent can reopen independently.

| ID | Identity to keep | Contract |
|---|---|---|
| K01 | Warm semantic colour system | Keep the warm neutral canvas, olive action colour, lime orientation accent and separate success, warning and danger roles. |
| K02 | Bilimbi geometry | Keep `rounded-xl` primary surfaces, compact `rounded-md` fields and table controls, the accepted action hierarchy, and hairline ledger structure. |
| K03 | Compact operational density | Preserve fast scanning, dense tables, compact controls and restrained spacing without becoming cramped. |
| K04 | Instrument Sans hierarchy | Preserve the current typeface, compact navigation scale and tabular numerals for comparable data. |
| K05 | Brand means orientation | Lime identifies orientation — selection, focus, active navigation, location and unseen-by-you markers (the aggregate unread count badge and the per-item unread dot); it never represents status. |
| K06 | Calm action language | Keep the deep-olive primary action, scarce emphasis and calm treatment of destructive work. |
| K07 | Bilimbi mark and wordmark | Keep the product mark, wordmark and local graphic identity. |
| K08 | Ledger page archetypes | Keep one shared width and hierarchy for list, form and detail pages. |
| K09 | Trustworthy behavior and voice | Feedback is truthful, accessible and recoverable; copy remains plain, calm and operational. |

### Parity Capability Catalog

The catalog is organized by what a human is trying to review, not by Laravel or Phoenix implementation. The assessment is a starting point to verify in the live products; it is not an automatic decision to port every Belimbing component.

Phase 0 verified every row against both live products. A row whose `Bilimbi now` or `Parity target` cell the evidence contradicted carries a [(contradicted)](#targets-the-evidence-contradicts) marker beside its ID: the original wording stays here as the record of what was accepted, and the correction is recorded once under [Targets the evidence contradicts](#targets-the-evidence-contradicts). Do not act on a marked row without reading it. A row the 2026-09-16 lane audits found understated, and that carries no marker, has its `Bilimbi now` cell corrected in the table itself to what ships, restated 2026-09-17; its `Parity target` keeps the accepted wording.

| ID | Design element | Bilimbi now | Parity target |
|---|---|---|---|
| FND-01 | Semantic colours | Strong identity and semantic roles | Keep Bilimbi; verify light/dark contrast and role separation. |
| FND-02 | Typography hierarchy | Present | Keep Bilimbi; verify headings, body, labels, help and tabular data. |
| FND-03 | Spacing and density rhythm | Partly standardized | Define one compact rhythm across primitives and page assemblies. |
| FND-04 | Shape, lines and elevation | Strong identity with local drift | Keep Bilimbi geometry; remove unexplained variations. |
| FND-05 | Focus, motion and reduced motion | Partial | Define consistent focus visibility, transition purpose and reduced-motion behavior. |
| FND-06 | Icon language and catalog | Registry exists; review is limited | Use Belimbing's established icon choices for equivalent actions, except logout, while rendering them through Bilimbi's icon component and registry. Add searchable visual review, empty result, copy and copied feedback. |
| LAY-01 | Authentication shell | Exists | Compare first impression, responsive behavior, errors and recovery. |
| LAY-02 [(contradicted)](#targets-the-evidence-contradicts) | Application shell and account footer | Exists | Remove persistent company and tenant repetition. Put the current timezone and light/dark theme selectors in the top bar. Keep the user circle at the bottom left as the account and scope entry point; show an always-visible warning only for unusual or safety-critical scope. Match the best collapse, drawer and navigation-continuity behavior. |
| LAY-03 | Page width and page header | Shared primitives exist | Cover title, subtitle, action, pin, contextual help and narrow states. |
| LAY-04 | Secondary side panel | Bespoke Design Library example | Establish one responsive page-local navigation pattern with desktop rail and mobile access. |
| LAY-05 | Index, form and detail geometry | Shared `<.page>` enforces one width per list, form and detail archetype; each screen still composes its assembly locally | Define complete assemblies rather than leaving every screen to compose them differently. |
| NAV-01 [(contradicted)](#targets-the-evidence-contradicts) | Main menu tree | Exists | Verify active ancestry, pinned items, reorder, collapse, mobile drawer and persistence. |
| NAV-02 | Tabs | Shared `<.tabs>` used by Schedule and Settings | Provide shared semantics, keyboard navigation, active state and URL/history rules. |
| NAV-03 | Link dictionary and related-link groups | No shared contract | Adopt internal, anchor, external, new-tab and download behavior; mutations remain buttons. |
| NAV-04 | Pagination | Shared component exists | Compare narrow layout, disabled states, page-size control, URL state and accessible labels. |
| NAV-05 [(contradicted)](#targets-the-evidence-contradicts) | User account and scope menu | Partial user footer exists | On user-circle activation, show signed-in name and identifier, current company and tenant, change password and sign out. Show scope switching only when more than one permitted scope exists. |
| ACT-01 [(contradicted)](#targets-the-evidence-contradicts) | Buttons | Primary, secondary and destructive basics | Cover emphasis, compact size, disabled, loading, navigation and truthful completion. |
| ACT-02 | Icon actions and groups | Shared icon button ships with inline and table sizes, accessible labels, native titles, and disabled and busy (spinner plus `aria-busy`) specimens; grouping is ad hoc (dashboard customize clusters) | Add grouping, context sizing, disabled/loading behavior and accessible tooltips. |
| ACT-03 | Destructive entry and acknowledgement | Inconsistent screen patterns | Standardize consequence copy, confirmation and typed acknowledgement where risk requires it. |
| INP-01 | Shared field shell | Shell ships label, hint, error, disabled and read-only placement, a visible required marker, `aria-invalid` on the control, and `aria-describedby` linking the control to its own hint and error ids; prefix and suffix do not exist | Standardize required, help, error, disabled, read-only, prefix and suffix placement. |
| INP-02 | Text, email, URL, telephone, number and textarea | Available through the generic input, which carries the INP-01 state contract (required, invalid, described-by, read-only) on text and textarea; the sizing contract and realistic long-content validation are untouched | Complete state and sizing contracts and validate realistic long content. |
| INP-03 [(contradicted)](#targets-the-evidence-contradicts) | Search | Generic search type | Add clear, empty, loading and result-update behavior. |
| INP-04 | Select, multi-select, checkbox and radio | Shared components for all four, including `<.radio_group>`; state coverage partial | Complete open/close, summary, no-options, outside-click, Escape and keyboard behavior. |
| INP-05 | Date, time, datetime and integer entry | Mostly native generic inputs | Define tabular display, step controls, validation and locale/timezone behavior. |
| INP-06 | Secret input | Password field only | Distinguish saved mask, reveal, replacement and explicit clearing. |
| INP-07 | Searchable and editable combobox | Missing | Adopt the useful Belimbing behavior with full keyboard, async, no-result and commit/cancel states. |
| INP-08 | Country and currency lookup | Missing | Build only the generic visual/interaction seam; domain data stays with its owning module. |
| INP-09 | Segmented control | Missing | Add for short peer choices when a real Bilimbi workflow needs it. |
| INT-01 | Inline text editing | Shared primitive exists | Complete F2/typing entry, Enter/blur save, Escape cancel, focus restore and error recovery. |
| INT-02 | Inline select, combobox and textarea editing | Missing | Add after their underlying controls are accepted. |
| INT-03 [(contradicted)](#targets-the-evidence-contradicts) | Grouped fact editing | Missing | Support Apply/Cancel where facts must change atomically. |
| INT-04 [(contradicted)](#targets-the-evidence-contradicts) | Disclosure | No shared primitive | Define open/closed semantics, `aria-expanded`, keyboard behavior and reduced motion. |
| INT-05 | Filter and period patterns | Repeated local compositions | Standardize the shared composition while keeping URL state and production meaning. |
| INT-06 | Unsaved-change and template selection flows | Missing | Defer until a real Bilimbi workflow proves the need. |
| FBK-01 | Inline alerts | Shared primitive exists | Verify status semantics, copy, contrast, icons and dismissibility. |
| FBK-02 | Flash and notification behavior | `Layouts.flash_group/1` is the one production outlet, restated 2026-09-17: four severities stack in one column, most severe first, click-to-dismiss throughout, info, warning, error and the reconnect notices stay until dismissed, and the Design Library presents all four; the shell's preference status line is a recorded exception. Still open: auto-dismiss, whose mechanism ships but lies dormant because only `:success` carries the eight-second timer and no caller emits a `:success` flash; the `:info` call sites (most report a completed write, which is why the colour repaint was reverted, while others report actionable failures, which is why `:info` stays sticky — both close, and the timer starts running, once those callers move to `:success`); and redirect continuity | Define stacking, timing, sticky warning/error, manual dismissal and redirect continuity. |
| FBK-03 | Validation, disabled and loading states | Partial: `<.button>` and `<.icon_button>` carry a `busy` state that spins, disables and announces `aria-busy`, distinct from plain disabled without depending on animation; the icon-button vocabulary now covers in-flight — `<.icon_button>` documents `phx-disable-with` as incompatible, because it deleted their glyph, and the employee-type delete runs async on `busy` instead — but that delete is so far its only adopter, and every other destructive icon action still shows nothing while its write runs; a `phx-disable-with` round trip is mirrored onto `aria-busy` by the shell but keeps the dimmed disabled look, so on that path loading and disabled are still one picture; login goes busy with readonly fields and announces credential and lockout failures through `role="alert"` on every attempt, a repeated identical message included; validation states are untouched | Make the states visibly distinct and prevent duplicate work. |
| FBK-04 | Empty, permission, unavailable, error and recovery states | Shared `<.empty_state>` (what is missing, why, optional recovery) reachable from `<.table>`'s `<:empty>` slot, with one owned permission wording; `/companies` adopts its nothing-yet and nothing-matched states and offers the first create only to an actor who may make one. Unavailable and error states remain the Schedule alerts and layout flashes | Adopt the region pattern on the remaining index and show-page tables; a nothing-yet region that also explains a missing create right is deferred until a workflow needs that sentence; unavailable/reconnect stays unverified. |
| OVR-01 [(contradicted)](#targets-the-evidence-contradicts) | Standard modal | Missing | Add accessible open, close, Escape, backdrop, focus containment and focus return. |
| OVR-02 [(contradicted)](#targets-the-evidence-contradicts) | Confirmation modal | Missing | Add consequence-first confirmation without copying Belimbing's accessibility gaps. |
| OVR-03 | Inspector drawer | Missing | Add only for a real inspector workflow; cover mobile width, resizing and remembered width. |
| OVR-04 | Tooltip and popover behavior | No shared contract | Define only where labels or contextual actions genuinely require it. |
| DAT-01 | Cards, facts and dense summaries | Shared card and definition-list fact rows exist; the Authz role detail adopts `<.list>` while `/companies/1` hand-writes its fact grid and dashboard summaries are ad hoc | Standardize metadata hierarchy and compact summary composition. |
| DAT-02 | Badges and status treatments | Basic badge exists | Complete neutral, information and status roles without using brand as status. |
| DAT-03 | Tables and sortable headings | Shared table exists | Cover caption, overflow, sticky header, hover, stripes, empty state, footer and truthful sorting. |
| DAT-04 [(contradicted)](#targets-the-evidence-contradicts) | Absolute and relative time | Absolute datetime exists | Add relative time only with the absolute value available. |
| DAT-05 [(contradicted)](#targets-the-evidence-contradicts) | Statistics and stat strips | Missing | Add when a dashboard or operational summary supplies a real use case. |
| DAT-06 | Record history, timeline and comparisons | Local or missing | Keep specialist behavior with the owning workflow; share only the generic presentation seam. |
| CMP-01 [(contradicted)](#targets-the-evidence-contradicts) | Operational index page | Partial specimen | Standardize header, filters, table, actions, empty/loading/error and pagination as one flow. |
| CMP-02 | Form page | Complete production form ships (`/companies/create`: field rhythm, inline validation, save/cancel); no unsaved-navigation guard exists, and that criterion depends on INT-06, which is deferred until a real Bilimbi workflow proves the need; the shared composition is not extracted | Standardize field rhythm, validation, save/cancel, loading, success and unsaved navigation. |
| CMP-03 | Detail and settings page | Complete production detail ships (`/companies/1`: facts, explicit edit modes, related navigation, permission states); the shared assembly is not extracted | Standardize facts, inline/grouped editing, related navigation and permission states. |
| CMP-04 | Destructive workflow | No complete specimen | Show entry, consequence, acknowledgement, in-flight, success, failure and recovery together. |
| CMP-05 | Authentication and first arrival | Login, recovery and dashboard arrival ship and were audited live against Belimbing (Lanes A and D); the sign-in handoff is a busy submit with readonly fields | Treat login, recovery and dashboard arrival as first-impression acceptance surfaces. |
| CMP-06 | Responsive and theme coverage | The `/companies` index and the shell were verified live at narrow width and in dark theme (Lane D); narrow detail, narrow form and a full keyboard pass remain | Review representative assemblies at desktop/narrow widths and in light/dark themes. |
| GFX-01 | Mark and wordmark | Present | Keep Bilimbi identity and verify size, surface and contrast uses. |
| GFX-02 | Product and interface icons | Registry and Heroicons exist | Make the approved FND-06 icon set searchable and verify size, alignment and meaning without copying Belimbing assets or framework markup. |
| GFX-03 | Placeholder and empty-state graphics | Limited | Add only when graphics improve comprehension rather than decorate empty space. |

### Disposition Ledger

Every catalog item receives one disposition after visual and interaction review:

- **Keep Bilimbi** — Bilimbi is already the better result; document and enforce it.
- **Equivalent** — capability and quality already match; fill only missing evidence.
- **Adopt adapted** — take Belimbing's useful behavior but render it through Bilimbi identity.
- **Steward review** — the design steward compares live alternatives, chooses the best supported treatment within K01–K09 and records the reason; this is temporary audit work, not a user approval queue.
- **Not applicable** — the capability has no honest Bilimbi use; record why and do not build it.

The ledger is campaign tracking, not a permanent second design source. Accepted outcomes move to the live Design Library, Design Spec and shared implementation under the same catalog ID.

#### Recorded dispositions (Phase 0, 2026-09-16)

All 57 rows verified against both live products. Bilimbi was read at `ff5a5a0` on a
private instance; Belimbing at `local.blb.lara`. The per-row working notes were not
kept as durable artifacts, so this document is the whole record: every row carries its
disposition and dependency, and the verification method is stated here only where the
evidence contradicted the catalog's target, surfaced a shipped defect, or could not be
obtained at all — the three subsections below. Auditing any other row means
re-deriving it from those two builds.

A disposition here is a starting position with evidence behind it, not an approval to
build. Where the evidence contradicted the catalog's own target, the row says so
rather than being quietly reconciled.

| ID | Disposition | Depends on |
|---|---|---|
| FND-01 Semantic colours | Keep Bilimbi | none |
| FND-02 Typography | Keep Bilimbi | none |
| FND-03 Spacing rhythm | Adopt adapted — named spacing roles, Bilimbi values | before LAY-05, CMP-01…03 |
| FND-04 Shape and elevation | Keep Bilimbi | none |
| FND-05 Focus and motion | Adopt adapted — one focus contract; reduced motion shipped as a single global `prefers-reduced-motion` rule in `app.css`, so no component carries `motion-reduce` | before ACT-01, INP-01 |
| FND-06 Icon language | Adopt adapted — searchable catalog; finish the migration | #719 |
| LAY-01 Authentication shell | Keep Bilimbi | none |
| LAY-02 Application shell | Adopt adapted — shipped in #711, confirmed live | none |
| LAY-03 Page header | Adopt adapted — responsive stacking, pin slot, help slot | NAV-01 pin decision; shared-component edit by the integration owner, not Phase 5 |
| LAY-04 Side panel | Adopt adapted | LAY-02 drawer mechanics, #719 |
| LAY-05 Page geometry | Keep Bilimbi | FND-03, LAY-03 |
| NAV-01 Menu tree and pins | Adopt adapted — pins become account state; `user_pins` is the sole store (steward, 2026-09-16) | unblocks LAY-03; adoption-URL question escalated |
| NAV-02 Tabs | Adopt adapted — ARIA tablist, arrow keys, one URL rule | none |
| NAV-03 Links | Adopt adapted | none |
| NAV-04 Pagination | Keep Bilimbi | none |
| NAV-05 Account menu | Adopt adapted — shipped in #711, confirmed live | multi-scope selector deferred (business decision) |
| ACT-01 Buttons | Adopt adapted | none |
| ACT-02 Icon actions | Keep Bilimbi | ACT-01 loading contract |
| ACT-03 Destructive entry | Adopt adapted | OVR-02, ACT-01 |
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
| FBK-01 Inline alerts | Adopt adapted | none |
| FBK-02 Flash | Adopt adapted | z-order agreed with OVR-01 |
| FBK-03 Validation, disabled, loading | Adopt adapted | ACT-01 |
| FBK-04 Empty, permission, error, recovery | Adopt adapted (empty and permission regions — one shared `<.empty_state>` with one owned permission wording; revised 2026-09-18 by the FBK-04 slice, from the Phase 0 "Keep Bilimbi") / Keep Bilimbi (unavailable and error — the existing alerts and layout flashes) | none |
| OVR-01 Standard modal | Adopt adapted — share the shell drawer's containment, do not re-add | extract containment hook from `app_shell.js` |
| OVR-02 Confirmation modal | Adopt adapted | OVR-01, ACT-03 |
| OVR-03 Inspector drawer | Not applicable — no workflow needs it | a real inspector workflow |
| OVR-04 Tooltip and popover | Equivalent | none |
| DAT-01 Record fact list | Keep Bilimbi — Belimbing hand-writes `<dl>` too | none for the API; migration is Phase 5 |
| DAT-02 Status and badges | Adopt adapted — `info` role only, never `accent` | a new `info` role in `@theme` (FND) |
| DAT-03 Tables | Keep Bilimbi (density, header case, sort) + Adopt adapted (accessible name, `title`) | shared-component edit; raw tables are Phase 5 |
| DAT-04 Timestamps | Keep Bilimbi (absolute) + Adopt adapted (relative) | none for the primitive; raw-format sites are Phase 5 |
| DAT-05 Stat cards | Adopt adapted — now, not later; already shipping | label/value scale should become shared tokens |
| DAT-06 Record history | Keep Bilimbi — ownership split is strictly better | `history` icon name depends on GFX-02 |
| CMP-01 Operational index | Keep Bilimbi on URL state and page sizes | settle one URL vocabulary before Phase 5 |
| CMP-02 Create and edit form | Keep Bilimbi | `aria-describedby` belongs to INP-01 |
| CMP-03 Detail page | Adopt adapted — one `detail_section` assembly on Bilimbi's archetype (steward, 2026-09-16) | DAT-01, FND-02, FND-03, LAY-03, INT-01, INT-02, DAT-03, GFX-02 |
| CMP-04 Destructive flow | Adopt adapted — take the acknowledge-input contract | OVR-01, OVR-02 |
| CMP-05 Authentication pages | Equivalent | none |
| CMP-06 Responsive and theme coverage | Adopt adapted — one recorded narrow-width and light/dark review per assembly, replacing ad hoc checks | CMP-01 to CMP-05; dark theme on the Lane B rows was not verified in Phase 0 |
| GFX-01 Identity mark | Keep Bilimbi | none |
| GFX-02 Icon assets | Adopt adapted — but reorder: register the missing names first | none for the registration fix |
| GFX-03 Illustration | Not applicable | none |

##### Steward decisions (2026-09-16)

**NAV-01 — pins are account state.** The server-side path is already built and
entirely unwired: the local shell landed 2026-08-17 and the `user_pins` API the next
day (#316), and nothing ever connected them. Verified live — pinning a nav item and a
record pin persisted across navigation while `user_pins` stayed at 0 rows and no
`/api/pins` traffic occurred. That is drift, not a recorded policy. `user_pins` becomes
the sole store; the scope carries a `:pins` snapshot beside `:shell_preferences`;
writes go through a `ShellPins` `attach_hook` twin of `ShellPreferences`, refusing
impersonated writes exactly as `DisplayPreferences.own_account/1` does, so
`PinController` and its routes are deleted rather than left as a second write path.
Rail, width and branch expansion stay deliberately browser-local. Reason: a
"Pin to sidebar" control that vanishes on another device fails silently against K09,
and the round trip is the cost already accepted for theme and time display in #711.

**CMP-03 — one detail assembly.** Bilimbi has five section-heading treatments, four
`dt` label treatments, three grid rules, two card paddings and three editing models
across six detail screens; on User and Employee the section title and the fact label
share a class string, so the hierarchy collapses. Belimbing has the same flaw but is
consistent everywhere — its consistency is what to take, not its uppercase styling.
One `detail_section` (title, count, description, `:actions`), `<.list layout={:grid}>`
for facts, inline editing per fact with a grouped Apply/Cancel only where facts change
together, no modal, and permission-less viewers see the value with no affordance
rather than a disabled control.

**Escalated — not a design decision.** Belimbing's stored `user_pins.url` values point
at `/admin/companies/1` while Bilimbi serves `/companies/1`. Whether adoption rewrites
known prefixes, deletes the rows, or leaves them dormant is a durable-data decision
under `docs/architecture/database.md`. The steward decided only the display rule: a pin
to a URL this installation does not serve is hidden.

##### Targets the evidence contradicts

These are recorded rather than reconciled, because the catalog was written before the
products were read and the plan forbids treating existence as acceptance.

- **CMP-01** — "Partial specimen" understates what ships: complete operational indexes
  already ship on `/companies`, `/users`, `/audit/mutations` and `/notifications`
  (Lane D), so the remaining work is one shared composition, not capability. Moving
  toward Belimbing would also be a regression. Belimbing keeps only
  `page` in the URL and offers 10/20/50/100 page sizes; Bilimbi already mandates
  25/50/100/300 with full URL state. One shipped exception: `/audit/mutations`
  hand-writes a Previous/Next pager instead of `<.pagination>` (Lane A), a Phase 5
  migration, not a pattern to copy.
- **DAT-05** — "Missing" is wrong. Five stat cards ship on `/dashboard`, duplicated
  into ten markup blocks with 65 arbitrary-value classes.
- **DAT-04** — relative time already ships in notifications, in a bare `<span>` with
  no `<time>`, no `datetime` and no `title`, frozen at render.
- **INT-03** — "Missing" is wrong. Bilimbi runs it in ten production LiveViews and
  Belimbing has no component either.
- **INP-03** — Belimbing *removes* the native clear affordance Bilimbi keeps; there is
  nothing to adopt.
- **OVR-01** — "Missing" understates, and moving toward Belimbing would be a
  regression. The shell drawer already implements `inert`, `aria-modal` and backdrop
  mechanics; the work is to share it, not to build it. Lane B observed through
  dispatched in-page events that Belimbing's shared modal does not move focus in, trap
  it or return it, and that two demo dialogs could be open at once — read together with
  the note below that Belimbing modal focus behaviour beyond dispatched events was not
  verified. Hand-written full-viewport overlays of the same fixed-inset,
  dimmed-backdrop shape also shipped in production across several modules, none
  of them carrying a dialog role, `aria-modal`, Escape or focus containment; Attach
  Address on `/companies/1` and Add Employee on `/users/1` were the two Lane B
  exercised live. The shared `<.modal>` has since replaced every one of them: a native
  `<dialog>` with a labelled title, focus in, containment and return, Escape, and an
  inert page behind, adopted by every production workflow overlay and shown at both
  widths in the Design Library. That meets the accepted target and exceeds Belimbing on
  focus and Escape, with one deliberate departure from its "backdrop" wording: clicking
  the dimmed page does not close, so a stray click cannot discard a form.
- **LAY-02, NAV-05** — the "Bilimbi now" cells describe pre-#711 state; both shipped.
- **INT-04** — reduced motion was not adoptable when Lane A measured it: neither
  product had a contract. Bilimbi now has one platform-wide under FND-05, so a
  disclosure primitive inherits it instead of defining its own.
- **NAV-01** — "reorder" in the target has no observed counterpart in Belimbing's
  navigation; pin-to-top covers the keep-favourites-handy need on both sides (Lane A).
  Dropped from parity acceptance rather than built to. Bilimbi does ship pinned drag
  reordering in the shell today — mouse-only, and saved to `localStorage` like the pins
  themselves. That order is account state: the pin drift recorded below leaves it in
  the browser, and the steward decision above makes `user_pins` the sole store, so
  `sort_order` and `reorder_user_pins/2` stay in scope when pins are wired. The
  mouse-only limitation is recorded below as a defect, not adopted here as a target.
- **ACT-01** — "basics" understates what ships: disabled, navigation-as-button and an
  in-flight `Working…` primary already render on the Design Library (Lane B), and a
  `busy` state that spins and announces `aria-busy` now ships beside them. The open
  work is a compact size and an in-flight treatment that stays visibly distinct from
  disabled on the `phx-disable-with` path, not the basics.
- **OVR-02** — "Missing" is true of a shared confirmation overlay only. Destructive
  work already confirms through the browser's native dialog, with consequence copy on
  some screens (Lane B), so the work is one accessible shared component rather than
  introducing confirmation. Read with the exception under Defects found while
  verifying: several destructive controls, authorization changes among them, fire with
  no confirmation at all, so migrating the existing `data-confirm` sites does not reach
  them.

##### Defects found while verifying

Not catalog work. These are user-facing faults in shipped code, listed so they are not
lost inside a design ledger:

- Eight destructive controls fire with no confirmation at all. Four change
  authorization, all in `core/user/.../show_live.ex`: `remove_role` (`:1109`),
  `remove_capability` on a direct grant (`:1260`), `deny_capability` (`:1271`) and
  `remove_capability` on a deny (`:1314`). `remove_capability` is listed twice
  deliberately — it backs two separate controls, and confirming only the first
  leaves the second live. Three remove dashboard content in
  `web/.../dashboard_live.ex`: `remove-section` (`:609` and `:650`) and
  `remove-widget` (`:723`). The eighth is `remove_activity`
  (`core/company/.../show_live.ex:982`), a hand-written button rather than a shared
  danger control. 22 `data-confirm` attributes across 17 files exist elsewhere, so
  the convention is established and these are the exceptions.
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
- Pinned reordering is mouse-only. `app_shell.js` wires HTML5 drag events on
  `[data-pinned-item]` with no keyboard or pointer-free equivalent, and the grip
  advertising it is `aria-hidden`, so keyboard and assistive-technology users cannot
  reorder pins at all.
- `<.header>` never stacks; its actions are clipped and unreachable at 420px, where
  Belimbing's header wraps.
- `:info` flashes render with success (green) roles.
- The Design Library labelled the sign-in mark 48px and rendered it at 48px, while the
  credential layout renders it at 36px. Fixed in this change: the specimen now renders
  and labels 36px, so the mark section shows the size actually in use.

##### Corrections to this document

- The Icon vocabulary slice below claimed `IconRegistry` carried 73 glyph entries.
  Corrected in place: it holds 3 glyph entries, 9 shell names and 49 named actions.

##### Inaccurate claims found in other project files

Not catalog work either, and not user-facing. Recorded so the next agent to touch
these files does not inherit the claim:

- The `/* Menu typography & font colors matching Belimbing */` rule in
  `apps/web/assets/css/app.css` says menu typography matches Belimbing. Belimbing
  renders 14px/400; Bilimbi renders 13px/350.
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

### The design steward owns routine design acceptance

Component-by-component human selection would interrupt the authorized campaign. An unrestricted whole-library rewrite would hide accumulated decisions and weaken verification. The accepted direction is autonomous steward stewardship in complete, bounded slices: inspect Belimbing visually and in source, implement through Bilimbi's shared foundations, verify the live specimen and a production workflow, then record evidence before proceeding. User review remains available without being a dependency.

The steward is a role, not one agent. Astra (`gpt-6-astra`) held it through
2026-09-15; Fable (`claude-fable-5-1`) holds it from 2026-09-16 at the user's
direction. Completed-work attributions below record whoever did the work at the
time and are historical facts rather than a statement of the current role.

Preserve K01–K09 and the user's explicit shell and icon requirements. Escalate only when the work requires a new business, security or durable data-contract decision outside the accepted scope. Routine geometry, interaction, icon mapping, responsive layout and accessibility judgments belong to the design steward. Shared-file ownership remains singular; delegated evidence and module adoption may proceed in parallel.

The first parity slice owns `LAY-02`, `NAV-05`, shell-related `FND-06`, timezone/theme utilities and desktop, collapsed-sidebar and narrow-drawer states. Subsequent slices follow dependency order rather than waiting for every family audit to finish.

### Account and tenancy context are disclosed when useful

Keeping company and tenant in the top strip makes known context compete with the current task. Hiding scope everywhere is also unsafe for platform operators, impersonation and cross-company work. The recommended direction is progressive disclosure: the bottom-left user circle opens one account menu containing identity, company, tenant and account actions. A switcher appears only for users who can switch. Unusual or safety-critical scope remains visible outside the menu as a persistent warning.

### Brand-strong text contrast (FND-01) is accepted

`text-brand-strong` text, measured by Lane A at 3.06:1 against the 4.5:1 bar at its real 12–13px size, was shown to the captain with both remedies, a darker text lime and reserving brand-strong text for large or bold use, and ruled: "Leave it; the current contrast is acceptable for this product." This is a deliberate accepted decision, not an open defect: later audits cite it instead of reopening it. The ruling covers both call-site families Lane A measured — active-navigation text in `layouts.ex` and the timezone panel's pressed choices in `shell_components.ex` — and nothing else. Lane A's other two contrast findings are now closed, by the separate palette change rather than by this ruling. C2, dark table-header ink at 3.64:1, closed by raising `--color-ink-subtle` in both dark blocks of `app.css`: it measures 5.35:1 on `surface`, 4.88:1 on `surface-sunken` and 4.64:1 on `surface-muted`, with light `ink-subtle` raised alongside it to 6.02:1, 4.79:1 and 5.52:1 on those same three surfaces, and `theme_contrast_test.exs` now gating each header pair at 4.5:1. C3, faint ink used as real text, closed at the one site Lane A measured as real text: the decision-log acting-for line moved from `text-ink-faint` (2.59:1 light, 2.29:1 dark on `surface`) to `text-ink-muted` (7.64:1 light, 6.76:1 dark, and 6.08:1 / 6.17:1 on the `surface-sunken` row hover). The other `text-ink-faint` uses are non-essential icons and placeholders and were never part of C3. Phase 0 recorded that it did not verify contrast beyond the automated test.

### Unseen-by-you markers (K05) are orientation

Lane D asked whether the notification unread count badge and per-item unread dot may use brand lime under K05. The captain ruled: "Keep both; tighten K05 wording to name unseen-by-you markers as orientation". Both keep lime, and the K05 row and `DESIGN.md`'s `brand` / `brand-strong` text now name unseen-by-you markers so the precedent is bounded by the written rule rather than by memory of this decision. No code changed.

## Public Contract

- Belimbing is reference evidence, not visual or implementation authority.
- Bilimbi identity IDs `K01`–`K09` are fixed constraints for parity work; the design steward resolves routine design choices within them.
- Ordinary company and tenant context is available through the bottom-left user account menu, not repeated in the top strip. Platform-operator, impersonated and other safety-critical scope remains visibly disclosed while active.
- The top bar exposes the current timezone and light/dark theme selectors. What a selection must do — apply immediately, persist for the signed-in user and render truthfully — is stated once in `DESIGN.md`'s application shell section.
- Equivalent actions use Belimbing's established icon choices through Bilimbi's icon registry, with logout as the explicit exception.
- Every parity issue names the catalog IDs it owns, its dependencies, affected routes, owned files and acceptance evidence.
- A catalog item is complete only when its disposition is recorded, the real component is shown in the Design Library, applicable states and keyboard behavior are tested, narrow and theme behavior are reviewed, and one production screen adopts it.
- The design steward accepts routine design choices from visual, interaction and production evidence; component and family completion does not require human selection. Unresolved business, security or durable data-contract decisions remain explicit blockers for the affected work only.
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

Validation: A new agent can tell what must remain Bilimbi, what is being compared, what is already equivalent, what the design steward decides and which business/security/data-contract questions require escalation.

### Phase 1 — Make the Design Library the parity workbench

Goal: Let the design steward or a product reviewer inspect one family at a time without a long, conflicting page.

- [x] Align the secondary menu with the catalog families: Foundations, Page Structure, Navigation and Links, Actions, Inputs, Interaction Patterns, Feedback and States, Overlays, Data Display, Composite Patterns and Graphics. `{claude-opus-families-1/claude-opus-5}`

  What the alignment exposed, recorded so the next slice does not rediscover it:

  - **Overlays was the only family with no specimen anywhere.** OVR-01 to OVR-04
    were all missing, so `#component-overlays` rendered its heading and said "No
    specimen yet" instead of being dropped from the menu. The shared `<.modal>`
    has since filled OVR-01 there; OVR-02 to OVR-04 are still missing.
  - **Foundations and Graphics are not empty; they are elsewhere.** The Theme
    area already is FND and the Graphic area already is GFX, so both keep one
    home and the family menu links to their routes rather than showing a second
    copy under Components.
  - **The section headed "Interaction patterns" was CMP-01.** Its search, table,
    empty result and pagination are one operational index flow, so it is now
    Composite patterns; Interaction patterns keeps INT-01 inline editing alone.
  - **`<.card>` and `<.badge>` moved to Data display** (DAT-01, DAT-02) and the
    application shell moved under Page structure (LAY-02), keeping its own
    `#component-shell` deep link as a nested menu-linked section.
  - **NAV-04 pagination still has no specimen of its own.** It renders twice,
    both times inside the table it pages, so it stays with Data display and
    Composite patterns; the coverage guard reports it as unpresented.
  - The eleven family entries carry letter prefixes (`A Foundations` through
    `K Graphics`), so the alphabetical ascending order root `AGENTS.md` §12
    requires and the catalog order that makes the alignment checkable are the
    same sequence. No exception to §12 is claimed or needed. Letters rather than
    numbers because the page already renders dozens of catalog IDs (`LAY-01`, `OVR-04`
    and so on): a numeric menu prefix sits beside those as a second numbering
    system a reader could reasonably think is related, and letters cannot be
    mistaken for a catalog ID. Letters also need no zero-padding, so a twelfth
    family cannot silently break the sort the way unpadded numbers would.

- [x] Separate family specimens into mergeable family-owned view boundaries while retaining one Design Library shell and production component source. `{codex-sol-specimens-1/gpt-5.6-sol}`
- [x] Show the current Bilimbi component in every meaningful state for the active family. `{codex-luna-states-1/gpt-5.6-luna}`

  Both landed on 2026-09-15 and neither finished the job: the `:design_library_drift`
  guards still report four failures on `main`, and this branch left the count
  unchanged. The shared modal (`OVR-01`) does add one name to the coverage guard's
  missing list: `connection_banners` is layout chrome that every page carries once
  and every open dialog carries again, so the Design Library presents it through
  the modal specimen rather than through an anchor of its own. A second live
  instance on that page would announce a dropped connection twice — the component
  has no presentational mode, and giving it one to satisfy a guard would be the
  guard shaping the product.
- [ ] Correct the four `:design_library_drift` specimen and state failures those two slices left, then move the guards into the default test run and `mix precommit`.
- [ ] Present alternatives under steward review together with recognizable use cases and stable catalog IDs; record the design steward's accepted disposition and rationale.
- [ ] Add focused coverage for variants, states and interactions; component-name presence alone is not enough.

Affected pages: `/system/design-library`, `/system/design-library/components`, `/system/design-library/graphic`, `/system/design-library/design-spec`

Validation: The reviewer can reach any catalog family quickly, interact with the real component and record a decision by stable ID.

### Phase 2 — Parallel family audits

Goal: Complete evidence and recommended dispositions without changing production design prematurely.

- [x] Lane A — audit FND, LAY and NAV against both applications and representative shell/page routes. `{crewmate scout, relaunched, model unrecorded}` — FND-06 was excluded from this lane by its brief, which told the scout not to audit it or build an icon inventory; the icon vocabulary was inventoried separately by a crewmate scout (`parity-icon-inventory/report.md`, 48 actions, held outside the repository like the lane reports), implemented through the registry by `{codex-terra-icons-1/gpt-5.6-terra}` (#715) and held to the Heroicons the build emits by `{fm/icon-registry-name-validity/opus-5}` (#727).
- [x] Lane B — audit ACT, FBK and OVR, including loading, dismissal, confirmation and recovery. `{crewmate scout, unsigned, model unrecorded}`
- [x] Lane C — audit INP and INT, including field shell, keyboard behavior, editing and rich choices. `{crewmate scout, unsigned, model unrecorded}`
- [x] Lane D — audit DAT, CMP and GFX, including actual index, form, detail, authentication and dashboard flows. `{crewmate scout, model unrecorded}`
- [ ] Integration owner consolidates reports into this ledger and removes duplicate or speculative targets.

The four lane audits ran on 2026-09-16 and produced evidence only; their reports are held outside the repository. What landed on 2026-09-17: seven understated rows — LAY-05, ACT-02, DAT-01, CMP-02, CMP-03, CMP-05 and CMP-06 — were restated in the catalog table above; the NAV-01, ACT-01 and OVR-02 corrections and the OVR-01 and CMP-01 additions were recorded under Targets the evidence contradicts; and the two captain rulings were recorded under Design Decisions. Nothing else from the four reports is claimed to be on file: consolidating them into this ledger remains open.

Validation: Every catalog item has evidence, a recommended disposition, dependencies and at least one real Bilimbi use case or a reason to omit it.

### Phase 3 — Shared parity foundations

Goal: Build accepted shared contracts in dependency order.

- [ ] Stabilize identity tokens, focus, field shell, card, icon and action foundations.
- [ ] FND-05 follow-up — make the vendored `topbar` navigation progress bar honor `prefers-reduced-motion` without losing an honest loading signal; it animates a canvas from JavaScript, so the global CSS rule cannot reach it.
- [ ] Implement accepted navigation, link and action contracts.
- [ ] Implement accepted native input, choice, feedback and data-display contracts.
- [x] Implement the accepted modal contract (`OVR-01`, Adopt adapted) as shared `<.modal>`, adopt it in every production workflow overlay and show both widths in the Design Library. `{fm/modal-a11y-dialog-semantics/opus-5}`
- [ ] Implement accepted combobox, edit-in-place, disclosure and confirmation contracts only after their foundations are stable.
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

Validation: the design steward's browser and interaction review confirms that parity improves real work and still looks and feels like Bilimbi, with recorded evidence for each assembly.

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

Deferred at delivery, closed by the follow-up on this branch: the impersonation label on the reader surfaces is now covered where each one renders it — `apps/base/audit/web_test/audit_live_test.exs` on the mutations and actions readers, `apps/core/employee/web_test/employee_show_test.exs` on record history. Each case asserts the operator attribution on an impersonated row and refutes it on an ordinary row in the same listing, so deleting a rendering clause turns the suite red.

Delivery: https://github.com/BelimbingApp/bilimbi/pull/714 merged on 2026-09-15, closing #712.

### Icon vocabulary slice — Issue #713

Goal: Give familiar actions named entries in the icon registry so call sites name the action rather than a raw `hero-*` string.

- [x] Inventory Belimbing's action icons against Bilimbi's registry; 48 actions mapped, 44 of them gaps. `{crewmate scout, model unrecorded}` — delivered as `parity-icon-inventory/report.md`, which the registry slice below consumed rather than re-gathered; it deliberately chose no glyphs.
- [x] Populate `IconRegistry` with the named action vocabulary, keeping logout as the recorded Bilimbi exception. `{codex-terra-icons-1/gpt-5.6-terra}`
- [x] Run the shipping gate and land the change. `{codex-terra-icons-1/gpt-5.6-terra}`
- [x] Follow-up after #715 — prove each named entry resolves to a Heroicon the build emits. `{fm/icon-registry-name-validity/opus-5}`

`IconRegistry` now carries 49 named actions on `main`, alongside the 3 Bilimbi glyph entries and 9 shell names it already had. The slice added the action vocabulary; the glyph count is unchanged by it.

Not delivered by this slice, and still open under FND-06 and GFX-02: the searchable visual icon review with empty-result, copy and copied feedback. The registry holds the vocabulary; no review surface presents it yet.

The deferred gap is closed, after this slice and outside #715: registry names are now checked against the icons the build can emit, not against a second copy of the map. `BilimbiWeb.HeroiconsManifest` derives the accepted `hero-` names from the Tailwind plugin's own icon directory and suffix table, and `apps/web/test/bilimbi_web/icon_name_validity_test.exs` holds both halves of the named vocabulary to them through `IconRegistry.actions/0` and `IconRegistry.shell_actions/0`; `menu_icon_safelist_test.exs` holds contributed menu Heroicons and the `app.css` safelist to the same names. A misspelled or upstream-removed glyph now fails the suite instead of rendering an empty span. Call sites that bypass the registry and pass a `hero-` name straight through remain unchecked.

Delivery: https://github.com/BelimbingApp/bilimbi/pull/715 merged on 2026-09-15, closing #713.

### Design Library workbench slices — Issues #718 to #721

Goal: Show real components in real states on the Design Library, and fail a test when
it stops doing so.

All four merged on 2026-09-15 and closed their issues:

| Issue | Work | PR |
|---|---|---|
| #718 | Design Library drift guards | https://github.com/BelimbingApp/bilimbi/pull/722 |
| #719 | Design Library specimen separation | https://github.com/BelimbingApp/bilimbi/pull/723 |
| #720 | Design Library missing component states | https://github.com/BelimbingApp/bilimbi/pull/716 |
| #721 | Shell display controls with live-following timestamps | https://github.com/BelimbingApp/bilimbi/pull/717 |

Not finished by #719 and #720: the `:design_library_drift` guards report four failures
on `main`, so #722's guards land excluded from the default test run and from
`mix precommit`. Correcting those four and activating the guards is the open Phase 1
checklist row above. #722 being merged does not mean the guards are active.

### Empty and permission region slice — no child issue

Goal: Close FBK-04's empty and permission half so a region with nothing in it
says which absence it is. Nothing created yet, nothing matched and not
permitted ask three different things of the person in front of them, and only
one of them is a dead end.

- [x] Add one shared `<.empty_state>` in `Bilimbi.Base.UI.Components`: a caller's `title` and `reason` with an optional recovery action, or the one permission wording the component owns (`forbidden`), never both. `apps/base/ui/test/components_empty_state_test.exs` holds the two modes, the different first-run and no-match sentences, and the raise on a call that says both or neither. `{fm/empty-and-permission-states/claude-fable-5-1}`
- [x] Reach the same pattern from `<.table>`'s `<:empty>` slot through `title`/`reason`/`forbidden` attrs, so a table says what is missing without a second component and plain slot content still renders as given. `{fm/empty-and-permission-states/claude-fable-5-1}`
- [x] Adopt it on `/companies`, the operational index page this slice canaries for Phase 4 — one accepted pattern on it, not yet the whole Phase 4 row: a search or status filter that matched nothing names what was narrowed and offers the way back, keeping sort and page size; an empty tenant says so and offers the first create only to an actor holding `admin.company.create`. Covered in `apps/core/company/web_test/company_live_test.exs`. `{fm/empty-and-permission-states/claude-fable-5-1}`
- [x] Present the three states in the Design Library's Feedback and states family as one `component-empty-state` block, retiring the hand-written `Empty workspace` and `Permission denied` specimen cards and their `DesignLibrarySource` declarations. `{fm/empty-and-permission-states/claude-fable-5-1}`

Not delivered by this slice, and still open under FBK-04: the remaining index and
show-page tables keep their own empty rows; a nothing-yet region that also
explains a missing create right was built and then removed in review, and stays
deferred until a workflow needs that sentence; unavailable and reconnect states
keep the existing Schedule alerts and layout flashes, which the ledger row
records as Keep Bilimbi.

Delivery: https://github.com/BelimbingApp/bilimbi/pull/740 merged on 2026-09-18.

### Field shell states slice — INP-01 and INP-02, partial

Goal: Make the shared field shell state what it is, so a person using assistive
technology hears what a sighted person sees.

Shipped in `Bilimbi.Base.UI.Components.input/1` and `multi_select/1`, exercised on
the Design Library and adopted by `/companies/create` and `/employees/new`:

| Gap | Delivered |
|---|---|
| A required field is not visibly marked | A marker on the label, `aria-hidden` because the control's own `required` attribute already announces it |
| An invalid field tells assistive technology nothing | `aria-invalid` on the control itself |
| Hint and error text are not associated with the control | Hint and error elements carry ids and the control points `aria-describedby` at them, so a field with both reaches the person with both |
| There is no read-only state | A read-only appearance driven by the `readonly` attribute the caller set, not by the CSS `:read-only` pseudo-class, which also matches every `select`, `color` and `file` control |
| A server-side required failure renders no field error appearance | Submitting an empty required field marks the control invalid and points it at its error, not only the message beside it |

Neither row is closed, and the code is what closes a row:

- **INP-01 remains open** for prefix and suffix placement. Neither exists in the
  shell. The disabled appearance and the red invalid border shipped before this
  slice and are unchanged by it.
- **INP-02 remains open** for the sizing contract and for validation against
  realistic long content. This slice touched neither.
