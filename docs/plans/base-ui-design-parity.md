# Base UI Design Parity

**Status:** In progress — Phase 0 is complete: all 57 catalog rows carry a disposition and dependency in the ledger below, and the Design Library's secondary menu is aligned with the eleven catalog families (#724). Merged to `main` through 2026-09-15: application shell, impersonation audit actor, the named icon vocabulary, Design Library specimen separation, state coverage, drift guards and live timestamp display. Since then the library has been stripped of catalog IDs (#728), and the shared layer has taken much of the accepted action and feedback contract — destructive confirmation (#733), reduced motion with 4.5:1 contrast (#738), stacked flash messages (#741), busy controls and a login screen that reports its progress (#743), the empty and permission region pattern (#740), real dialog semantics on modal overlays (#731), one shared filter toolbar (#745), field shell states (#744), secret reveal and multi-select corrections (#746) and a released shell observer (#747) — alongside icon-name validity (#727, #734), Schedule timestamps and UTC day labels through the datetime component (#735, #737), impersonation reader coverage (#729), corrected catalog rows (#730), drift-guard documentation folded into this plan (#726) and the Belimbing cutover value remap (#725); the drift guards stay excluded from the default run — the Design Library state-coverage slice of 2026-09-18 corrected all but two of the uncovered names and axes the coverage guard reports and records those two as accepted rather than pending, and the anchor-hygiene slice of 2026-09-23 cleared the imitation guard's anchor failures, leaving one hand-written control-markup failure (the example `<nav>` rail) open
**Last Updated:** 2026-09-23
**Sources:** `docs/plans/base-ui-design-library.md`; `DESIGN.md`; root `AGENTS.md`; Issue #691; https://github.com/BelimbingApp/bilimbi/pull/696 (merged); [campaign #709](https://github.com/BelimbingApp/bilimbi/issues/709); [shell #710](https://github.com/BelimbingApp/bilimbi/issues/710) (closed by #711); [audit actor #712](https://github.com/BelimbingApp/bilimbi/issues/712) (closed by #714); [icon registry #713](https://github.com/BelimbingApp/bilimbi/issues/713) (closed by #715); [drift guards #718](https://github.com/BelimbingApp/bilimbi/issues/718) (closed by #722); [specimen separation #719](https://github.com/BelimbingApp/bilimbi/issues/719) (closed by #723); [state coverage #720](https://github.com/BelimbingApp/bilimbi/issues/720) (closed by #716); [display controls #721](https://github.com/BelimbingApp/bilimbi/issues/721) (closed by #717); `apps/base/ui/`; `apps/web/assets/css/app.css`; Belimbing `UiReferenceSection`, UI Reference partials, shared UI components, `tokens.css`, and `components.css`
**Agents:** `crewmate/gpt-6` (`agent:kiatng-sol-medium`); `astra_pr_gate/gpt-6-astra` (autonomous design steward, through 2026-09-15); `claude-fable-steward-1/claude-fable-5-1` (autonomous design steward, from 2026-09-16); `claude-fable-audit-1/claude-fable-5-1`; `codex-terra-icons-1/gpt-5.6-terra`; `claude-fable-guards-1/claude-fable-5-1`; `codex-sol-specimens-1/gpt-5.6-sol`; `codex-luna-states-1/gpt-5.6-luna`; `claude-opus-datetime-1/claude-opus-5`; `claude-opus-families-1/claude-opus-5`; `claude-opus-motion-contrast-1/claude-opus-5`; `fm/modal-a11y-dialog-semantics/opus-5`; `fm/empty-and-permission-states/claude-fable-5-1` (Claude Code running Claude Fable 5.1); `fm/parity-plan-checklist-reconcile/muse-spark` (checklist reconciliation on 2026-09-18, not audit authorship); `fm/icon-registry-name-validity/opus-5`; `fm/designlib-state-coverage-gaps/opus-5` (Design Library state coverage on 2026-09-18); `fm/addresses-detail-read-first/opus-5` (read-first detail page, shared commit status and demoted back link on 2026-09-20); `fm/companies-detail-belimbing-parity/claude-fable-5-1` (company detail header settled against Belimbing on 2026-09-20: the history icon, demoted Manage links and no header buttons); `fm/companies-detail-read-first/claude-fable-5-1` (company detail facts read-first on 2026-09-23); `fm/records-whose-only-page-is-a-form/claude-fable-5-1` (employee type record page read-first and the employee and employee-type edit routes retired on 2026-09-23); `fm/designspec-codes-off-the-ui/claude-fable-5-1` (Design Spec numbers dropped from the rendered card headings on 2026-09-23); `crewmate scout` (firstmate scout tasks that record no model — the FND-06 icon inventory and the four Phase 2 lane audits of 2026-09-16; separate sessions from the `crewmate/gpt-6` entry above, which is why these rows carry no model)

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
| K01 | Warm semantic colour system | Keep the warm neutral canvas, olive action colour, lime orientation accent and separate success, info, warning and danger roles. |
| K02 | Bilimbi geometry | Keep `rounded-xl` primary surfaces — table frames and the cards that frame them excepted, which are flat — compact `rounded-md` fields and table controls, the accepted action hierarchy, and hairline ledger structure. |
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
| LAY-05 | Index, form and detail geometry | Shared `<.page>` enforces one width per archetype: list and detail share `max-w-7xl`, as Belimbing gives a detail the same column as a list, and form keeps `max-w-2xl`; each screen still composes its assembly locally | Define complete assemblies rather than leaving every screen to compose them differently. |
| NAV-01 [(contradicted)](#targets-the-evidence-contradicts) | Main menu tree | Exists | Verify active ancestry, pinned items, reorder, collapse, mobile drawer and persistence. |
| NAV-02 | Tabs | Shared `<.tabs>` used by Schedule and Settings | Provide shared semantics, keyboard navigation, active state and URL/history rules. |
| NAV-03 | Link dictionary and related-link groups | Two shared entries: `<.back_link>`, the demoted "← Back" return link every list, form and detail page uses instead of a "Back to …" button, and `<.action_link>`, the demoted related-workflow link with its registry glyph that the Departments and Relationships sections of `/companies/1`, the Department Types and Legal Entity Types links on `/companies` and the Employee Types link on `/employees` use instead of buttons | Adopt internal, anchor, external, new-tab and download behavior; mutations remain buttons. |
| NAV-04 | Pagination | Shared component exists | Compare narrow layout, disabled states, page-size control, URL state and accessible labels. |
| NAV-05 [(contradicted)](#targets-the-evidence-contradicts) | User account and scope menu | Partial user footer exists | On user-circle activation, show signed-in name and identifier, current company and tenant, change password and sign out. Show scope switching only when more than one permitted scope exists. |
| ACT-01 [(contradicted)](#targets-the-evidence-contradicts) | Buttons | Primary, secondary and destructive basics | Cover emphasis, compact size, disabled, loading, navigation and truthful completion. |
| ACT-02 | Icon actions and groups | Shared icon button ships with inline and table sizes, accessible labels, native titles, and disabled and busy (spinner plus `aria-busy`) specimens; grouping is ad hoc (dashboard customize clusters) | Add grouping, context sizing, disabled/loading behavior and accessible tooltips. |
| ACT-03 | Destructive entry and acknowledgement | Consequence-first `<.confirm_dialog>` on every destructive control; no `data-confirm` remains in the product, and the schedule's enable confirms the fingerprint it approves to run unattended, while resume runs on click as in Belimbing; typed acknowledgement stays unbuilt until a high-risk workflow needs it | Standardize consequence copy, confirmation and typed acknowledgement where risk requires it. |
| INP-01 | Shared field shell | Shell ships label, hint, error, disabled and read-only placement, a visible required marker, `aria-invalid` on the control, and `aria-describedby` linking the control to its own hint and error ids; prefix and suffix do not exist | Standardize required, help, error, disabled, read-only, prefix and suffix placement. |
| INP-02 | Text, email, URL, telephone, number and textarea | Available through the generic input, which carries the INP-01 state contract (required, invalid, described-by, read-only) on text and textarea; the sizing contract and realistic long-content validation are untouched | Complete state and sizing contracts and validate realistic long content. |
| INP-03 [(contradicted)](#targets-the-evidence-contradicts) | Search | Generic search type | Add clear, empty, loading and result-update behavior. |
| INP-04 | Select, multi-select, checkbox and radio | Shared components for all four, including `<.radio_group>`; state coverage partial | Complete open/close, summary, no-options, outside-click, Escape and keyboard behavior. |
| INP-05 | Date, time, datetime and integer entry | Mostly native generic inputs | Define tabular display, step controls, validation and locale/timezone behavior. |
| INP-06 | Secret input | Password field only | Distinguish saved mask, reveal, replacement and explicit clearing. |
| INP-07 | Searchable and editable combobox | Shared `<.combobox>` ships the single-value, client-filtered case: a hidden field carries the committed value, typing filters and highlights the first match without a round trip, arrow keys move, Enter commits the highlighted option and never submits the form, Escape or leaving restores the last choice, and no-options and no-matches states are distinct; async loading and free-text editing do not exist | Adopt the useful Belimbing behavior with full keyboard, async, no-result and commit/cancel states. |
| INP-08 | Country and currency lookup | Country uses `<.combobox>` with module-owned options on `/companies/create`, the Company jurisdiction fact and every Address country field; currency lookup is missing | Build only the generic visual/interaction seam; domain data stays with its owning module. |
| INP-09 | Segmented control | Missing | Add for short peer choices when a real Bilimbi workflow needs it. |
| INT-01 | Inline text editing | Shared `<.inline_edit>` commits on Enter or blur, cancels on Escape, shows `—` for a blank value, keeps the stored value on screen for the whole round trip, marks that trip `aria-busy` beside a "Saving…" line, and reports the commit outcome on the field itself through the shared `<.commit_status>`; an emptied input is a real edit only where the owner passes `allow_empty`. `/addresses/:id`, `/users/:id` and `/companies/:id` adopt all of it, and `/companies/:id` also passes `placeholder` so an always-empty control that adds rather than edits names its addition instead of `—`; the other inline-edit screens still report through a flash. F2 entry and focus restore after a commit do not exist | Complete F2/typing entry, Enter/blur save, Escape cancel, focus restore and error recovery. |
| INT-02 | Inline select, combobox and textarea editing | Shared `<.inline_choice>` owns the read-state trigger, window Escape cancel and `<.commit_status>` for every choice fact; the caller supplies its select or combobox editor, commit event and options. Adopted by the Address verification status, the User company, the Employee department, supervisor, type and status, and the Company choice facts, including the jurisdiction `<.combobox>`; no inline textarea exists | Add after their underlying controls are accepted. |
| INT-03 [(contradicted)](#targets-the-evidence-contradicts) | Grouped fact editing | Missing | Support Apply/Cancel where facts must change atomically. |
| INT-04 [(contradicted)](#targets-the-evidence-contradicts) | Disclosure | No shared primitive | Define open/closed semantics, `aria-expanded`, keyboard behavior and reduced motion. |
| INT-05 | Filter and period patterns | Repeated local compositions | Standardize the shared composition while keeping URL state and production meaning. |
| INT-06 | Unsaved-change and template selection flows | Missing | Defer until a real Bilimbi workflow proves the need. |
| FBK-01 | Inline alerts | Shared primitive exists | Verify status semantics, copy, contrast, icons and dismissibility. |
| FBK-02 | Flash and notification behavior | `Layouts.flash_group/1` is the one production outlet, restated 2026-09-17: four severities stack in one column, most severe first, click-to-dismiss throughout, info, warning, error and the reconnect notices stay until dismissed, and the Design Library presents all four; the shell's preference status line is a recorded exception. Completed writes now flash `:success`, so the eight-second timer runs for every one of them, and a LiveComponent panel reports under the same kind rule through `<.panel_notice>`. `:info` now paints on its own blue `info` role and success and info are announced as a polite `status` while warning and error stay an assertive `alert`, matching Belimbing's alert. Still open: redirect continuity | Define stacking, timing, sticky warning/error, manual dismissal and redirect continuity. |
| FBK-03 | Validation, disabled and loading states | Partial: `<.button>` and `<.icon_button>` carry a `busy` state that spins, disables and announces `aria-busy`, distinct from plain disabled without depending on animation; the icon-button vocabulary now covers in-flight — `<.icon_button>` documents `phx-disable-with` as incompatible, because it deleted their glyph, and the employee-type delete runs async on `busy` instead — but that delete is so far its only adopter, and every other destructive icon action still shows nothing while its write runs; a `phx-disable-with` round trip is mirrored onto `aria-busy` by the shell but keeps the dimmed disabled look, so on that path loading and disabled are still one picture; login goes busy with readonly fields and announces credential and lockout failures through `role="alert"` on every attempt, a repeated identical message included; validation states are untouched | Make the states visibly distinct and prevent duplicate work. |
| FBK-04 | Empty, permission, unavailable, error and recovery states | Shared `<.empty_state>` (what is missing, why, optional recovery) reachable from `<.table>`'s `<:empty>` slot, with one owned permission wording; `/companies` adopts its nothing-yet and nothing-matched states and offers the first create only to an actor who may make one. Unavailable and error states remain the Schedule alerts and layout flashes | Adopt the region pattern on the remaining index and show-page tables; a nothing-yet region that also explains a missing create right is deferred until a workflow needs that sentence; unavailable/reconnect stays unverified. |
| OVR-01 [(contradicted)](#targets-the-evidence-contradicts) | Standard modal | Missing | Add accessible open, close, Escape, backdrop, focus containment and focus return. |
| OVR-02 [(contradicted)](#targets-the-evidence-contradicts) | Confirmation modal | `<.confirm_dialog>` on the shared modal: consequence-first `alertdialog`, calm danger confirm, Cancel first and focused, Escape cancels, no typed acknowledgement; adopted by every destructive control, so no native confirm remains | Add consequence-first confirmation without copying Belimbing's accessibility gaps. |
| OVR-03 | Inspector drawer | Missing | Add only for a real inspector workflow; cover mobile width, resizing and remembered width. |
| OVR-04 | Tooltip and popover behavior | No shared contract | Define only where labels or contextual actions genuinely require it. |
| DAT-01 | Cards, facts and dense summaries | Shared card and definition-list fact rows exist; the Authz role detail adopts `<.list>` while `/companies/1` hand-writes its fact grid and the dashboard's audit and performance summaries are ad hoc | Standardize metadata hierarchy and compact summary composition. |
| DAT-02 | Badges and status treatments | Basic badge exists | Complete neutral, information and status roles without using brand as status. |
| DAT-03 | Tables and sortable headings | Shared table exists | Cover caption, overflow, sticky header, hover, stripes, empty state, footer and truthful sorting. |
| DAT-04 [(contradicted)](#targets-the-evidence-contradicts) | Absolute and relative time | Absolute datetime exists | Add relative time only with the absolute value available. |
| DAT-05 [(contradicted)](#targets-the-evidence-contradicts) | Statistics and stat strips | Missing | Add when a dashboard or operational summary supplies a real use case. |
| DAT-06 | Record history, timeline and comparisons | Local or missing | Keep specialist behavior with the owning workflow; share only the generic presentation seam. |
| CMP-01 [(contradicted)](#targets-the-evidence-contradicts) | Operational index page | Partial specimen | Standardize header, filters, table, actions, empty/loading/error and pagination as one flow. |
| CMP-02 | Form page | Complete production form ships (`/companies/create`: field rhythm, inline validation, save/cancel); no unsaved-navigation guard exists, and that criterion depends on INT-06, which is deferred until a real Bilimbi workflow proves the need; the shared composition is not extracted | Standardize field rhythm, validation, save/cancel, loading, success and unsaved navigation. |
| CMP-03 | Detail and settings page | Three production details ship: `/addresses/1` and `/users/1` are read-first (every fact edits in place and saves by itself — the user's company is a choice that becomes a select on click — one grouped Apply for the interdependent location facts, the outcome on the fact rather than in a flash, a demoted back link and the labelled history action; `/users/1` also carries Impersonate as a demoted `POST` action, and History is the only header button, a disclosure), and `/companies/1` is the third read-first adopter (every Company Details fact edits in place — seven text facts, four choice facts and the default-timezone setting as a fifth — business activities grow through the same in-place control and metadata keeps a single-fact Apply, each reporting on itself); its header matches Belimbing's history-and-back actions — the labelled history action and a back link, with Departments and Relationships reached through each section's demoted Manage link, and the status badge leading that row is Bilimbi's own #685 decision that Belimbing does not present; every detail page now takes the list width, as Belimbing's `admin/*/show` pages fill the main column; related navigation and permission states exist on all three, and the shared assembly is not extracted | Standardize facts, inline/grouped editing, related navigation and permission states. |
| CMP-04 | Destructive workflow | The Design Library's Overlays section shows the whole flow on example records: entry, consequence, in flight, success, failure and recovery; typed acknowledgement is deliberately absent | Show entry, consequence, acknowledgement, in-flight, success, failure and recovery together. |
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

The ledger is campaign tracking, not a permanent second design source. Accepted outcomes move to the live Design Library, Design Spec and shared implementation under the same catalog ID; the ID lives in this plan, HTML comments, test names and element ids — never in rendered text.

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
| NAV-01 Menu tree and pins | Adopt adapted — pins become account state; `user_pins` is the sole store, written only through the `/api/pins` controller (steward, 2026-09-16; write path amended 2026-09-24) | unblocks LAY-03; adoption-URL question escalated |
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

**NAV-01 — pins are account state.** *Superseded in part 2026-09-24; see the
amendment after this decision.* The server-side path is already built and
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

**NAV-01 amendment (2026-09-24) — the controller is the one write path.** The
`ShellPins` hook, the scope's `:pins` snapshot and the deletion of `PinController`
above are superseded. Pins are written only through the existing authenticated
`PinController` (`/api/pins/toggle|reorder`) over `user_pins`, and the shell syncs
from `GET /api/pins`; there is no `ShellPins` hook and no second write path. The
controller refuses writes from an impersonated session. `user_pins` remaining the sole
store, and rail, width and branch expansion staying browser-local, still stand.

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
  into ten markup blocks with 65 arbitrary-value classes. The Companies, Users,
  Sessions and Performance cards now render through the shared `<.stat_strip>`, with
  a Data display specimen, as Belimbing's Performance widget does. The recent-audit
  card keeps its own markup: it is a feed of entries, not label and value pairs.
- **DAT-04** — relative time already ships in notifications, in a bare `<span>` with
  no `<time>`, no `datetime` and no `title`, frozen at render. It has since been
  replaced: `/notifications` and the `/users` Created column render through
  `<.datetime>`, absolute as Belimbing shows them, so no relative time ships.
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
  LAY-02's always-visible-warning target was narrowed on 2026-09-22: see its
  disposition row and the shell operator marker slice below.
- **INT-04** — reduced motion was not adoptable when Lane A measured it: neither
  product had a contract. Bilimbi now has one platform-wide under FND-05, so a
  disclosure primitive inherits it instead of defining its own.
- **NAV-01** — "reorder" in the target has no observed counterpart in Belimbing's
  navigation; pin-to-top covers the keep-favourites-handy need on both sides (Lane A).
  Dropped from parity acceptance rather than built to. Bilimbi does ship pinned
  reordering in the shell: drag, plus Move up and Move down buttons for keyboard
  users. That order is account state, saved through `user_pins.sort_order` and
  `reorder_user_pins/2` like the pins themselves.
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
  the convention is established and these are the exceptions. Resolved: the five
  authorization and activity controls confirm (#733) and every `data-confirm`
  has since moved onto `<.confirm_dialog>`; the dashboard layout controls were
  deliberately left unconfirmed as one-click-reversible preferences.
- `<.multi_select>` cannot be closed by Escape or by its own toggle, and its
  `aria-expanded` is the literal `"false"` at `components.ex:669` — it never changes,
  so assistive technology is told the panel is shut while it is open.
- `<.inline_edit>` drops focus to `document.body` on every Enter-commit; Escape
  returns focus correctly. The blank-commit half of this defect is closed: an emptied
  input is a real edit where the owner passes `allow_empty`, and the outcome of a
  commit is reported on the field rather than by a flash that can go stale.
- Four icon names — `bilimbi-plus`, `bilimbi-pencil`, `bilimbi-link-slash`,
  `bilimbi-x-mark` — are unregistered across 11 call sites, so "add", "edit", "unlink"
  and "remove" all render the registry's fallback glyph.
- Per-user pins are built twice and shipped once: `PinController`,
  `/api/pins/toggle|reorder`, `User.toggle_user_pin/reorder_user_pins` and the
  `user_pins` table exist, and `app_shell.js` calls that API zero times while using
  `localStorage` ten times. Pins do not follow the account.
  Resolved: the shell loads pins from `GET /api/pins` and writes through
  `/api/pins/toggle|reorder`. It imports legacy browser navigation pins once and
  drops legacy record pins.
- Pinned reordering is mouse-only. `app_shell.js` wires HTML5 drag events on
  `[data-pinned-item]` with no keyboard or pointer-free equivalent, and the grip
  advertising it is `aria-hidden`, so keyboard and assistive-technology users cannot
  reorder pins at all.
  Resolved: each pinned item has Move up and Move down buttons.
- `<.header>` never stacks; its actions are clipped and unreachable at 420px, where
  Belimbing's header wraps.
- `:info` flashes render with success (green) roles.
- The Design Library labelled the sign-in mark 48px and rendered it at 48px, while the
  credential layout renders it at 36px. Fixed in this change: the specimen now renders
  and labels 36px, so the mark section shows the size actually in use.

##### Corrections to this document

- The Icon vocabulary slice below claimed `IconRegistry` carried 73 glyph entries.
  Corrected in place: it holds 3 glyph entries and 9 shell names beside the named
  action vocabulary, which later slices keep extending — `IconRegistry.actions/0`
  is the count, not this document.

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

Family specimens stay in the shared template behind the existing Design Library shell; the family-owned view split is dropped (see the dropped Phase 1 item below) — the few remaining Design Library slices rebase on the one template instead. Do not split the production component API merely to create artificial agent concurrency.

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

Keeping company and tenant in the top strip makes known context compete with the current task. Hiding scope everywhere is also unsafe for platform operators, impersonation and cross-company work. The recommended direction is progressive disclosure: the bottom-left user circle opens one account menu containing identity, company, tenant and account actions. A switcher appears only for users who can switch. Unusual or safety-critical scope remains visible outside the menu as a persistent warning. Revised 2026-09-22: only impersonation, which carries an exit, stays outside the menu; the standing platform-operator marker moved into it, as the shell operator marker slice below records and `DESIGN.md`'s application shell section states.

### Brand-strong text contrast (FND-01) is accepted

`text-brand-strong` text, measured by Lane A at 3.06:1 against the 4.5:1 bar at its real 12–13px size, was shown to the captain with both remedies, a darker text lime and reserving brand-strong text for large or bold use, and ruled: "Leave it; the current contrast is acceptable for this product." This is a deliberate accepted decision, not an open defect: later audits cite it instead of reopening it. The ruling covers both call-site families Lane A measured — active-navigation text in `layouts.ex` and the timezone panel's pressed choices in `shell_components.ex` — and nothing else. Lane A's other two contrast findings are now closed, by the separate palette change rather than by this ruling. C2, dark table-header ink at 3.64:1, closed by raising `--color-ink-subtle` in both dark blocks of `app.css`: it measures 5.35:1 on `surface`, 4.88:1 on `surface-sunken` and 4.64:1 on `surface-muted`, with light `ink-subtle` raised alongside it to 6.02:1, 4.79:1 and 5.52:1 on those same three surfaces, and `theme_contrast_test.exs` now gating each header pair at 4.5:1. C3, faint ink used as real text, closed at the one site Lane A measured as real text: the decision-log acting-for line moved from `text-ink-faint` (2.59:1 light, 2.29:1 dark on `surface`) to `text-ink-muted` (7.64:1 light, 6.76:1 dark, and 6.08:1 / 6.17:1 on the `surface-sunken` row hover). The other `text-ink-faint` uses are non-essential icons and placeholders and were never part of C3. Phase 0 recorded that it did not verify contrast beyond the automated test.

### Operator-facing surfaces carry the idea, not its identifier

#728 dropped the catalog IDs (`LAY-02`, `NAV-05` and the rest) from the Design Library after the captain called them confusing to operators. The Design Spec cards kept their numbers (`T01`, `D01`–`D06`, `C01`–`C06`) on the recommendation that they remain a citable ledger. The captain ruled on 2026-09-23: "Do not show catalog IDs on the UI, they are just noise to users", extending the same judgment to those cards. The rendered heading of each card is now the statement alone; the number survives only as the card's `id` (`spec-d01`), which the tests reach and which no visible text repeats. The numbers stay in this plan, the Design Library plan, `DESIGN.md`, comments and test names, in the same order, and nothing is renumbered. `DESIGN.md` "Write for humans" states the rule, and the Design Library's metadata test refuses any heading that leads with a code of that shape on every library screen. Renumbering or restructuring Design Spec, and the Design Library's own navigation, are separate work.

### Unseen-by-you markers (K05) are orientation

Lane D asked whether the notification unread count badge and per-item unread dot may use brand lime under K05. The captain ruled: "Keep both; tighten K05 wording to name unseen-by-you markers as orientation". Both keep lime, and the K05 row and `DESIGN.md`'s `brand` / `brand-strong` text now name unseen-by-you markers so the precedent is bounded by the written rule rather than by memory of this decision. No code changed.

## Public Contract

- Belimbing is reference evidence, not visual or implementation authority.
- Bilimbi identity IDs `K01`–`K09` are fixed constraints for parity work; the design steward resolves routine design choices within them.
- Ordinary company and tenant context is available through the bottom-left user account menu, not repeated in the top strip, and so is the standing platform-operator marker. Impersonation, which has an exit, remains visibly disclosed above the workspace while active.
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
    has since filled OVR-01 there and `<.confirm_dialog>` OVR-02; OVR-03 and
    OVR-04 are still missing.
  - **Foundations and Graphics are not empty; they are elsewhere.** The Theme
    area already is FND and the Graphic area already is GFX, so both keep one
    home and the family menu links to their routes rather than showing a second
    copy under Components.
  - **The section headed "Interaction patterns" was CMP-01.** Its search, table,
    empty result and pagination are one operational index flow, so it is now
    Composite patterns; Interaction patterns keeps INT-01 inline editing alone.
    The read-first detail slice added the demoted back link under Navigation and
    links (NAV-03), beside Navigation and Tabs, rather than here, and the
    company header parity slice added the action link beside it.
  - **`<.card>` and `<.badge>` moved to Data display** (DAT-01, DAT-02) and the
    application shell moved under Page structure (LAY-02), keeping its own
    `#component-shell` deep link as a nested menu-linked section.
  - **NAV-04 pagination has no card of its own.** It renders twice, both times
    inside the table it pages, so it stays with Data display and Composite
    patterns. The `<.pagination>` call that pages the canonical table now
    carries the `component-pagination` anchor as its own id, so the coverage
    guard no longer reports it as unpresented.
  - The eleven family entries carry letter prefixes (`A Foundations` through
    `K Graphics`), so the alphabetical ascending order root `AGENTS.md` §12
    requires and the catalog order that makes the alignment checkable are the
    same sequence. No exception to §12 is claimed or needed. Letters rather than
    numbers because the page then rendered dozens of catalog IDs (`LAY-01`,
    `OVR-04` and so on, since dropped from the product by #728): a numeric menu
    prefix sat beside those as a second numbering system a reader could
    reasonably think was related, and letters cannot be mistaken for a catalog
    ID. Letters also need no zero-padding, so a twelfth family cannot silently
    break the sort the way unpadded numbers would.

- [x] Separate family specimens into mergeable family-owned view boundaries while retaining one Design Library shell and production component source. **Dropped 2026-09-23:** the problem it was written for — fake specimens drifting away from the real components — was already solved by #723 (which replaced hand-written navigation, tabs and radio specimens with the real components) plus the route guards. Splitting the 1,369-line template would touch every anchor and all 14 web tests, and only a few Design Library slices remain, so rebasing those is cheaper than the split. `{codex-sol-specimens-1/gpt-5.6-sol}`
- [x] Show the current Bilimbi component in every meaningful state for the active family. `{codex-luna-states-1/gpt-5.6-luna}`

  Both landed on 2026-09-15 and neither finished the job: the `:design_library_drift`
  guards still report four failures on `main`, and this branch left the count
  unchanged. The shared modal (`OVR-01`) does add one name to the coverage guard's
  missing list: `connection_banners` is layout chrome that every page carries once
  and every open dialog carries again, so the Design Library presents it through
  the modal specimen rather than through an anchor of its own. A second live
  instance on that page would announce a dropped connection twice — the component
  has no presentational mode, and giving it one to satisfy a guard would be the
  guard shaping the product. Superseded 2026-09-23 by the `revealed` state
  recorded under the coverage entry below: the library presents the banners
  static, so the layout's pair stays the page's only live outlet.
- [x] Correct the `:design_library_drift` failures those two slices left, then move the guards into the default test run and `mix precommit`.

  Reconciled by the Design Library state-coverage slice of 2026-09-18, measured
  with `mix test --include design_library_drift` against `2b4a7e8` and against
  the slice. The same four guard tests fail before and after; what changed is
  what two of them report, from twenty-five uncovered names and axes down to two
  accepted gaps. `{fm/designlib-state-coverage-gaps/opus-5}`

  - **Coverage, component presence — three of four closed.** `icon`,
    `multi_select` and `pagination` had no `component-<name>` entry of their own
    and now have one. Two needed no new drawing: `pagination`'s sits on the
    `<.pagination>` call the canonical table already had rather than on a
    second copy of the control, and `icon`'s spans the Graphic page's
    registered glyphs and Heroicons rather than a second drawing under Actions.
    `multi_select` earned a specimen of its own, because its `hint` and `label`
    states had to be shown. The fourth, `connection_banners`, is accepted
    rather than pending, for the reason recorded above: the layout renders one
    pair on every page, so a second live pair here would tell an operator
    "Connection interrupted" twice on a real disconnect. Presenting it honestly
    needs a suppression seam in the shared component and in `app.css`, which is
    its own slice. **Closed 2026-09-23:** `<.connection_banners>` gained
    `revealed` (`:client` or `:server`), which renders that one banner shown
    and bound to no connection event. The library presents both under
    Feedback and states without adding a live outlet, so a disconnect on that
    page is reported once, by the layout's pair or an open dialog's, and no
    suppression seam is needed.
  - **Coverage, declared states — all but one closed.** Twenty-one axes across
    `filter_toolbar`, `icon`, `input`, `list`, `multi_select`, `radio_group`,
    `table` and `tabs` were presented in a single state; every one is varied now
    except `<.filter_toolbar>`'s optional `<:control>` slot, which is accepted.
    A toolbar with no control renders an empty form, a state no production
    screen builds, so the specimen that carried that reading was removed rather
    than kept as decoration. Closing it means declaring the slot required in the
    shared component, which is a component decision rather than a library one.
  - **Imitation, anchor claims and hand-written control markup — unchanged.**
    The same eleven `component-*` anchors that name no shared component or never
    call the one they name, and the same two raw elements (the example `<nav>`
    rail and the live-state `<dl>`), still fail. Both stay open.

  Both guards therefore still fail, stay tagged `:design_library_drift`, and stay
  out of the default run and `mix precommit`.

  - **Imitation, anchor claims — closed by the anchor-hygiene slice of
    2026-09-23.** The eleven anchors had two causes, both in the library.
    Nested `component-*` sub-ids fractured an entry: `<.page>`, `<.header>`
    and `<.list>` were called only inside `component-page-list`,
    `component-header-default`, `component-list-populated` and their
    siblings, which the guard reads as entries of their own, so the parent
    anchor never called what it claimed. And scaffolding wore the prefix:
    the choice-guidance card, the live-state card, the radio-group gap
    note, the card and list boundary notes, the locked radio group and the
    shell-rows card named guidance, a caption or a specimen that is not a
    shared component. Twenty ids moved to the library's own
    `design-library-` prefix (the fifteen the reported anchors needed plus
    the five nested sub-ids under `<.card>`, `<.tabs>` and `<.icon_button>`
    that fractured the same way without yet tripping it), every selector in
    `web_test/design_library_live_test.exs` moved with them, and the three
    cards that lost the prefix — Navigation, Choice guidance and Live state
    — are declared in `@declared_specimens`, which is the rule's own
    admission list. The live-state `<dl>` is now a `<.list>`, so that raw
    element is gone. The guard itself is unchanged, and so are the
    qualified sibling entries (`component-input-states`,
    `component-table-framed` and the like), which the rule reads as the
    named component's specimen qualified by what it shows.
    `{fm/designlib-anchor-hygiene/claude-fable-5-1}`
  - **Imitation, hand-written control markup — one left.** The example
    `<nav>` rail around the shell's `Layouts.nav_branch` rows still fails.
    No shared component owns that wrapper: the shell writes its own `<nav>`
    in `Layouts.app`, and a `<div>` carrying `role="navigation"` or an
    `aria-label` would trip the same rule or misuse ARIA. Closing it means
    extracting the rail wrapper into a shared component, which is a
    component decision rather than a library one, so it stays open beside
    the coverage gaps below.

  - **Coverage reads verified routes.** `DesignLibrarySource` used to classify
    every `~p` sigil as a runtime value, so a specimen could register a
    presence axis for `navigate`, `href` or `patch` only by passing a bare
    string, which is what root `AGENTS.md` section 9 forbids for internal
    paths; the read-first `/users/:id` slice made that trade and reversed it
    (#754). A `~p` whose path is wholly literal now normalises to the string
    it wraps, and a `~p` that interpolates, carries modifiers or sits inside a
    larger expression stays dynamic, both covered on fixtures in
    `design_library_rules_test.exs`. No specimen still carries a bare string
    for that reason. The `<.action_link>` `navigate` axis therefore shows
    `:present` and needs `:absent`, which only an `href` specimen can give;
    the `href` and `method` axes are unchanged. A request-form specimen
    needs a POST destination the library does not have, so those three axes
    stay open beside the `<:control>` slot.
  - **Both guards active — closed 2026-09-24.** Measured again on `32654ee`
    with `mix test --include design_library_drift`: the coverage guard
    reported the three `<.action_link>` axes, `<.filter_toolbar>`'s
    `<:control>` slot and `<.datetime>`'s `precision`, and the imitation
    guard reported the example `<nav>`. Each was corrected in the library or
    the component, and neither guard changed.
    `Layouts.nav_menu/1` now owns the labelled `<nav>` and its
    `.app-nav-rail` class, the shell's sidebar menu renders through it, and
    so does the Navigation card, so the library no longer writes the
    wrapper. A second `<.action_link>` sends a `POST` to
    `/system/design-library/components/specimen-request`, a no-op route
    Base UI contributes behind the Design Library capability, which changes
    no session or audit state and returns to the Components page; that
    gives `href` and `method` their present state and `navigate` its absent
    one. To mount it, `BilimbiWeb.DiscoveredRoutes` now mounts
    module-declared controller routes as well as LiveView routes. `<.filter_toolbar>` declares its
    `<:control>` slot required, since a toolbar with no control is an empty
    form no list builds, and the library shows a search-only toolbar beside
    the full one. The timestamp card adds a to-the-second instant. The
    `:design_library_drift` tag and its exclusion are gone, so both guards
    run in every `mix test` and in `mix precommit`.
- [ ] Record dispositions in the ledger as steward review closes; the accepted choices already live in the Design Spec cards and this plan's ledger. **Rewritten 2026-09-23:** the in-library alternatives surface with catalog IDs is dropped — only one row (INP-09) is still at steward review, catalog IDs are ruled out of the rendered library, and building a surface for a one-row queue is speculative.
- [ ] Add focused coverage for variants, states and interactions; component-name presence alone is not enough.

Affected pages: `/system/design-library`, `/system/design-library/components`, `/system/design-library/graphic`, `/system/design-library/design-spec`

Validation: The reviewer can reach any catalog family quickly, interact with the real component and record a decision by stable ID in the plan ledger.

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
- [x] FND-05 follow-up — the vendored `topbar` navigation progress bar honors `prefers-reduced-motion` with a static full-width loading bar; the canvas trickle and fade are not CSS, so the global rule cannot reach them. `{fm/parity-topbar-motion}`
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
- [x] Build the Design Library drift guards at the start of the campaign instead of at closeout, so later slices land against them rather than accumulating drift: `apps/base/ui/test/design_library_imitation_test.exs` rejects anchors that name no shared component, hand-written control markup and undeclared specimen cards; `design_library_coverage_test.exs` requires a `component-<name>` block per component and variation on the states it declares, showing at least two of an axis's declared states where it declares two or more and the single one where it declares one. Both read the template through `Bilimbi.Base.UI.DesignLibrarySource`, which owns the rules and is covered on fixtures by `design_library_rules_test.exs`. Both landed tagged `:design_library_drift` and out of the default run until the specimens they reported were corrected; since 2026-09-24 they run in every `mix test` and `mix precommit`. `{claude-fable-guards-1/claude-fable-5-1}`
- [ ] Add guards for raw palette use, local component forks, missing Design Library states and unregistered icons where deterministic checks are useful.
- [ ] Run component, LiveView, module workflow, asset and full precommit validation.
- [ ] Record the accepted dispositions in this plan and in HTML comments — catalog IDs stay in the plan, comments, test names and element ids, never in rendered text — and close the execution issues with browser evidence.

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
| LAY-02 safety context | Adopt adapted | Routine scope moves into the account menu. Platform-operator and impersonated access remain above the workspace, including when the narrow drawer covers content. Existing warning surface/line/ink roles preserve contrast in both themes. Ordinary scope has no warning; impersonation retains its stop action. Revised 2026-09-22: the platform-operator half moved into the account menu; see the shell operator marker slice below. |
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

The slice added the named action vocabulary beside the 3 Bilimbi glyph entries and 9 shell names the registry already had, and left the glyph count unchanged. Later slices keep naming actions in it — `history` landed with the read-first detail page — so `IconRegistry.actions/0` is what counts them.

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

Not finished by #719 and #720: the `:design_library_drift` guards reported four failures
on `main`, so #722's guards landed excluded from the default test run and from
`mix precommit`. The state-coverage slice of 2026-09-18 corrected most of what those
four reported, the anchor-hygiene slice of 2026-09-23 cleared the anchor rule, and the
remaining specimens were corrected on 2026-09-24, when both guards joined the default
run. The Phase 1 checklist row above records what each step closed.

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

### Read-first detail page slice — INT-01, INT-03, CMP-03 and NAV-03, partial

Goal: Let an operator change a fact where they read it, and let the fact itself
say what happened, so a detail page needs neither an edit mode nor a flash to
report a write.

Shipped in `Bilimbi.Base.UI.Components` and adopted on `/addresses/:id`:

- [x] `<.inline_edit>` keeps the stored value on screen for the whole round trip, marks the field `aria-busy` beside a "Saving…" line, renders `—` for a blank value, and commits an emptied input only where the owner passes `allow_empty`, so a required fact is never blanked by a stray Enter. `{fm/addresses-detail-read-first/opus-5}`
- [x] One shared `<.commit_status>` is the single voice for every write that saves by itself — the inline edit, the choice that commits on change and the grouped Apply all render it, so "Saved" and a named refusal cannot drift into three dialects. `{fm/addresses-detail-read-first/opus-5}`
- [x] `<.back_link>` replaces every "Back to …" button and every hand-written return link — Base Authz roles, Core Address, Company, Employee and User screens, and the credential pages — so returning is a plain "← Back" link in the header rather than a button competing with the work of the page, or prose above the header in its own colour. `{fm/addresses-detail-read-first/opus-5}`
- [x] The `record.history` trigger is demoted to the registry's new `history` clock at the toolbar icon size, the glyph Belimbing uses for the same action, keeping "History" for assistive technology and the tooltip. `{fm/addresses-detail-read-first/opus-5}`
- [x] `/addresses/:id` adopts all of it: text facts in place, the verification status committing on change, the four interdependent location facts behind one grouped Apply, viewers without `admin.address.update` seeing values with no affordance, and history reading both Belimbing-era and Bilimbi-written mutation rows. `{fm/addresses-detail-read-first/opus-5}`

Not delivered by this slice:

- **INT-02 stays missing.** The verification-status choice is a page-local
  select, not a shared inline-select primitive; inline combobox and textarea
  editing are untouched.
- **The other inline-edit screens are unmigrated.** `/employees/:id`,
  `/users/:id` and the Geonames lists still pass no `status` and no
  `allow_empty`, so they keep reporting through a flash.
- **INT-01's focus restore is still open**, and with it the `document.body`
  focus drop recorded under Defects found while verifying.
- **The Phase 4 detail row stays open.** This is one accepted pattern on one
  detail page, not the recorded narrow-width, dark-theme and keyboard review
  that row asks for.

### Demoted related-workflow link slice — NAV-03 and CMP-03, partial

Goal: Finish the canonical "secondary actions are links rather than buttons"
instruction globally, so a control that only carries the operator to a related
workflow never competes with the work its page is about.

Shipped in `Bilimbi.Base.UI.Components`:

- [x] `<.action_link>` is the general form of `<.back_link>` — the same
  `text-link` treatment and free text. Its surface is closed: `id`, `icon`,
  `navigate` and `title`, all four required, with no `class` override and no
  global attrs, so a demoted action that is unaddressable, unreachable,
  glyphless, unnamed or styled out of the family is unrepresentable. `title` is
  mirrored onto `aria-label`, which is what lets two "Manage" links on one page
  announce different destinations. The Design Library presents it as one titled
  specimen. `{fm/companies-detail-belimbing-parity/claude-fable-5-1}`

Converted call sites: the Departments and Relationships **Manage** links on
`/companies/:id`; **Department Types** and **Legal Entity Types** on
`/companies`; **Employee Types** on `/employees`, keeping its
`admin.employee-type.list` guard. A multi-line sweep of `<.button>` with
`navigate`, `href` or `patch` across `apps/*/lib`, `apps/*/*/lib` and
`apps/web/lib` found no other production violation — every survivor is its
page's own primary action.

**Placement decision.** Belimbing has no counterpart: every operational index
there carries only its primary create button in the page-header actions slot
and places no demoted related-workflow link beside it. The `/companies` order
therefore decided — primary action first, demoted links after — and
`/employees` was reordered to match, so the two indexes read identically. The
shared `<.header>` actions container is a plain block with no gap, so each such
row wraps its controls in a `flex items-center gap-3` row at the call site —
the value `/addresses/:id` already shipped with; the shared component is
untouched because every other page depends on it.

Left as arguable and unchanged:

- **`companies-clear-search`** and the `/companies` empty-state recovery patch
  button recover from a filter rather than navigating to a sibling workflow.
- **The Design Library's own "Navigation" button specimen** exists to present
  `<.button>`'s navigation mode; demoting it would delete the thing under
  review.

Not delivered by this slice:

- **Seven shipped pages still place `<.back_link>` before their primary
  button**, against the order settled above: Core Company's
  `departments_live.ex`, `relationships_live.ex`, `legal_entity_types_live.ex`
  and `department_types_live.ex`; Core Employee's `type_index_live.ex` and
  `show_live.ex`; and Core User's `show_live.ex`. The same seven header rows
  also still lack the `flex items-center gap-3` wrapper the rule above settles,
  so their controls sit one collapsed space apart. Both gaps pre-date this
  slice and are deferred together for a later change.
- **CMP-03 stayed open here.** `/companies/:id` still kept its facts behind
  explicit edit modes after this slice; only the header and the section
  affordances were settled. The company detail read-first slice below closed
  that gap.

### Shell operator marker slice — LAY-02 safety context, revised

Goal: stop telling the platform operator who they are on every screen, while
keeping the one strip that carries an exit.

The captain's ruling (2026-09-22): remove the strip; mark the status in the
account popup behind the bottom-left circle; label it "Platform-operator", in
the strip's own colour and background. "Owner" was rejected because the flag
sits on the tenant's company, and an account inside that company may still
lack access on the operator-only surfaces, so ownership would tell that person
something untrue about their standing.

Shipped in `Bilimbi.Base.UI.ShellComponents`:

- [x] `scope_warning/1` renders only while impersonating, with its "Viewing as
  … · Stop" link unchanged. Without impersonation there is no strip and no
  reserved space. `{fm/shell-operator-marker-and-topbar-spacing}`
- [x] `account_menu/1` adds an `Access` row below Tenant, labelled
  "Platform-operator", only when the scope's tenant carries
  `is_platform_operator`. It uses the `warning-surface`, `warning-ink` and
  `warning-line` tokens and the registry's `warning` glyph, so it reads as a
  caution in both themes, and it names the company's status rather than a
  personal entitlement. No capability or impersonation guard changed.
- [x] Top-bar controls fit inside the bar. The bar is `h-7`; the theme
  `<.icon_button>`s were `size-7` (the table default) and the timezone button
  `h-7`, so their pressed and hover surfaces painted the bar's bottom border
  and the window's top edge. The trailing horizontal padding was already the
  same 12px as the leading side. Both controls are now the sidebar toggle's
  `size-6` inline size, the timezone wrapper is a flex box so the two align,
  and the controls container may shrink so the impersonation-locked notice
  truncates at phone width instead of overflowing the brand.

Checked live at desktop and phone widths, in light and dark themes, with and
without impersonation. Coverage: the strip absent for an operator who is not
impersonating and present with its stop link while impersonating (for an
operator too); the marker present for an operator scope with the caution
tokens and absent otherwise; the dashboard asserting the marker in the panel
and no strip.

Not delivered by this slice: the operator-only surfaces themselves, such as
the raw SQL console, did not warn that an action is unfiltered. The operator
surface caution slice below closes that gap.

### Operator surface caution slice — LAY-02 safety context, completed

Goal: put a caution where an action or a listing genuinely is not filtered to
one company, on the screen itself, saying what is unfiltered rather than who
the operator is.

Belimbing evidence, read at the reference checkout before choosing a form: it
does not caution on either surface. The database console answers a
non-operator tenant with 403 (`RequiresPlatformOperatorTenant`) and its blade
carries no scope note; its decision log offers the operator an "All tenants"
checkbox and captions the table "(all tenants)" or "(current tenant)"
(`AuditTenantScope::retentionCaption`), so a widened read is opt-in and named
in a caption. Its roles list shows system roles to every tenant. Bilimbi's
widening is different in kind: `Authz.Administration.company_visibility/2`
adds company-less rows for the platform-operator scope on the decision log and
principal listings, and company-less assignments to the roles list's
Principals counts, with no toggle, and the console reads without any tenant predicate at all.

Shipped:

- [x] `Bilimbi.Core.User.Web.DatabaseQueriesLive.Show` renders
  `<.alert kind={:warning}>` inside the SQL editor card, between the Run
  Query row and the parameter inputs, reading "Not filtered to one company:
  SQL run here reads across every company and tenant in the database." It is
  the one prominent form, because a query there is unbounded; it is not a
  gate, and `Database.execute_readonly/3` is unchanged.
- [x] The three widened listings — Decision Logs, Principal Capabilities and
  Principal Roles — carry a one-line `text-warning-ink` caption with the
  registry's `warning` glyph directly above the table, "Beyond this tenant's
  companies: this list also includes … attached to no company." A caption
  rather than a banner, following Belimbing's shape, because the widening is
  a standing property of the rows. The listings' queries are unchanged.
- [x] The Roles listing's rows are not widened — every scope sees the same
  roles — but each row's Principals count is, so it carries the same caption
  reading "Beyond this tenant's companies: the Principals counts also include
  assignments attached to no company." Its query is unchanged.
- [x] Both render only for a platform-operator scope. Coverage: each of the
  five surfaces asserts the caution, by id and warning token, for the
  operator scope, and each listing asserts its absence for a fully-capable
  account in an ordinary tenant; the console's non-operator refusal at mount
  is already covered.

Follow-ups, deliberately not built here: any change to what the console or
the listings query; any confirmation step; the account-menu marker itself;
and the user detail page's role panel, which `list_principal_role_assignments`
widens the same way but which is a detail section rather than a listing.

### User detail Belimbing parity slice — CMP-03, INT-02, LAY-05 and NAV-03, partial

Goal: Bring `/users/:id` to the read-first, demoted-action shape `/addresses/:id`
and `/companies/:id` settled, and settle the detail page width against what
Belimbing actually does, under the captain's five canonical instructions of
2026-09-20 applied globally.

What Belimbing does, read from `resources/core/views/livewire/admin/users/show.blade.php`
and its shared components on 2026-09-22:

- **No width of its own.** The page is a `space-y-section-gap` stack inside a
  `<main class="flex-1 … px-1 sm:px-4">`; no `admin/*/show` page and no layout
  wrapper sets a `max-w-*`, so the cards fill the main column beside the
  sidebar at every viewport. The facts inside a card are
  `grid grid-cols-1 md:grid-cols-2 gap-4`.
- **A quiet labelled header row.** `x-ui.record-history` renders a ghost
  button (clock + "History"; none of the four `admin/*/show` pages passes
  `icon-only`), Impersonate is a ghost button (glyph + "Impersonate", a `POST`
  form, disabled for oneself and while impersonating) and Back is a plain
  `x-ui.link`. There is no edit button: the facts edit in place.
- **The company is `x-ui.edit-in-place.select`.** It reads as the company name
  or "None" with a hover pencil, becomes a focused select on click, saves on
  change, and closes on Escape (reverting) or blur.

Shipped:

- [x] `<.page variant={:detail}>` takes the list width `max-w-7xl` instead of
  `max-w-4xl`. Belimbing gives a detail the same column as a list; a detail's
  sections carry the same tables an index does; and the layout no longer jumps
  between `/users` and `/users/1`. The cap only binds on a main column wider
  than 80rem, where Bilimbi's lists already stop — on a 1920px display the
  cards leave the sidebar's remaining ~190px on each side, on a 1440px or
  1366px display they fill the column exactly as Belimbing's do, and at phone
  width they fill it. The one alternative, no cap at all, would have made a
  detail wider than its own index above 1536px and was not taken. Prose
  descriptions inside the user page's sections carry `max-w-prose`; the cards
  fill. `{fm/users-detail-belimbing-parity/claude-fable-5-1}`
- [x] The `record.history` trigger is a labelled action: the clock beside the
  word "History" in `demoted_action_class/0`, the treatment `<.back_link>` and
  `<.action_link>` share and the one public class in Base UI, exposed because
  the trigger is a `<summary>` and cannot be a link. The previous slice had
  kept the word for assistive technology only; Belimbing shows it on every
  detail page. Company, address, employee and user headers inherit it.
  `{fm/users-detail-belimbing-parity/claude-fable-5-1}`
- [x] `<.action_link>` accepts `href` and `method` in place of `navigate` for
  a quiet action that submits a request; exactly one destination is allowed
  and anything else raises. Impersonate on `/users/:id` is the first user,
  with its guards unchanged. `{fm/users-detail-belimbing-parity/claude-fable-5-1}`
- [x] `/users/:id` is read-first: the "Edit user" button is gone; name and
  email are `<.inline_edit>` facts with `status` (no `allow_empty`: both are
  required); the company reads as its name and becomes a select on click,
  commits on change, cancels on Escape or blur, and reports through
  `<.commit_status>` with the operator's choice named in a refusal; every
  outcome lands on its fact and success does not flash. The header is the
  `flex flex-wrap items-center gap-3` row of History, Impersonate and "← Back"
  and no button. An unaffiliated account has no company for Core User to
  write its facts through, so its name and email show no editor and an info
  notice says why; the company choice stays. Web tests cover a
  saved and a refused text commit (format and uniqueness), a saved, cancelled
  and refused company choice, the unaffiliated state, the viewer without
  `admin.user.update` seeing plain values, and History and Impersonate staying
  hidden from an actor without `admin.audit.log.list` and
  `admin.user.impersonate`. `{fm/users-detail-belimbing-parity/claude-fable-5-1}`
- [x] The company fact tells the truth about which rule refused it and about
  what clearing it costs. Reassign and clear both authorize
  `admin.user.update` against the account's **current** company, so their
  refusals name that company; the earlier "you may not manage users of that
  company" pointed at the chosen one, and on a clear at nothing at all. The
  unaffiliated notice has two branches because the rule has two outcomes:
  inside the platform-operator tenant it names
  `admin.user.unaffiliated.manage`, elsewhere `assign_unaffiliated_user/5`
  refuses on `tenants.is_platform_operator` before the capability. Neither
  branch, and neither refusal, offers re-affiliation as a recovery —
  `get_tenant_user/2` resolves a user through its company and no route
  reaches `list_unaffiliated_users/2`, so an unaffiliated account is
  reachable only from the LiveView that cleared it, and both say so. Because
  that is irreversible, choosing "None" no longer commits on change: it
  replaces the select with a
  `<.button variant="danger" id="user-company-clear-confirm">` whose
  `data-confirm` names the account, the sessions ended and the loss of every
  screen, beside a Cancel that restores the read state; `phoenix_html`
  confirms a click and not a select's change (PR #733), and the confirmed
  click re-asks Authz. This is the one place the page leaves Belimbing's
  behaviour deliberately: Belimbing's select saves the blank on change
  because it has a surface that manages an unaffiliated account afterwards,
  and Bilimbi has none, so copying it would be parity in shape rather than
  in substance. The captain may overrule it. That control is `phx-disable-with` for its round trip
  and the handler is idempotent — an account that already has no company has
  nothing to remove, so a confirmed click that arrives after the removal
  landed leaves the stored outcome standing instead of reporting a completed
  destructive write as refused. Its event is `remove_company` rather than
  `clear_company` so that `write_handler_guard_test.exs` recognises the most
  destructive event on the page as write-shaped; `clear` is in neither its
  `@write_verbs` nor its `@exact_writes`, and widening those lists would drag
  in unrelated `clear_notice` opt-outs. The unreachable `:employee_not_found` refusal is gone
  — the page passes no `employee_id` to any of the three transitions. Web
  tests cover the armed-but-unwritten blank choice, the `data-confirm` copy,
  Cancel, the confirmed clear, a refused clear naming the current company,
  and the notice in both a platform-operator and an ordinary tenant.
  `{fm/users-detail-belimbing-parity/claude-fable-5-1}`

- [x] The company choice offers companies only. The captain overruled the
  guarded "None": a user always belongs to a company and is the same person
  operating under a different one, so the page no longer detaches an
  account at all. The blank option, the `remove_company` event, the
  `confirm_clear_company?` assign, the danger confirmation and the
  unaffiliated notice are gone; the choice commits on change like every
  other choice fact and like Belimbing's select, and a blank value that
  still arrives is refused on the fact ("a user always belongs to a
  company") without a write. The one cost the operator could not see —
  `reassign_user_company/6` ends every session the account holds — is now a
  `text-warning-ink` note beside the open select, named by its
  `aria-describedby`, before the choice is made; it is a warning, not a
  second click. A user whose company is archived reads as "Archived
  company" in the fact and the subtitle instead of "None" and
  "Unaffiliated". `clear_user_company/5` stays in the API with a note that
  nothing offers it. Web tests cover the select without a blank option, the
  warning in the open editor and not in the read state, a refused blank, a
  refused reassignment naming the current company, and the viewer without
  `admin.user.update` seeing no select, no warning and no editors.
  `{fm/user-company-no-detach/claude-fable-5-1}`

Not delivered by this slice, reported as follow-up:

- **`clear_user_company/5` has no caller outside its tests.** Removing the
  write path, or giving it an operator surface, is a separate decision.
- **The rest of `/users/:id`** — the roles and capability pickers, the
  change-password disclosure, the employee records and external accesses
  sections — keep their existing buttons, flashes and permanent controls.
  Belimbing's page has the same sections; their own read-first migration is a
  separate slice.
- **`/users/:id/edit` is retired** by the records-whose-only-page-is-a-form
  slice below; `FormLive` is create-only.
- **No unaffiliated-users surface.** Nothing routes to
  `list_unaffiliated_users/2` or `get_unaffiliated_user/3`. The detail page
  no longer creates such accounts, but accounts already detached in
  existing data stay unreachable; shipping a surface for them is a captain
  decision and is not taken here.
- **The commit-status plumbing stays duplicated.** `put_field_status/3`,
  `drop_saved/1`, `refusal_message/3`, `rejected_value/1` and `fact_label/1`
  exist on both `/addresses/:id` and `/users/:id`. Extracting them beside
  `<.commit_status>` in Base UI is its own task, so that `/addresses/:id` is
  not edited from this change.
- **`/employees/:id`** still carries an "Edit employee" primary button and
  reports in-place edits through a flash (delivered by the employee detail
  slice below); **`/companies/:id`** still keeps its
  facts behind edit modes (CMP-03 stays partial). **Superseded 2026-09-23:**
  both are read-first now. The employee detail slice below removed the "Edit
  employee" button and the flash, and the company detail slice below removed
  the page-wide edit mode; neither page retains its header edit button. CMP-03
  is no longer partial on these two pages.
- **INT-02 stays without a shared primitive.** The user's company is the
  second page-local inline select on the same rule; extracting one shared
  `<.inline_select>` waits for its underlying control to be accepted.
- **The `<.header>` change is the narrow-width stacking only** (title first,
  actions below, under `sm`, as Belimbing's page header does; measured on
  `/users/2` at 390px: the title row is one line again and the actions row
  sits below it at the page's left edge). Each detail page still supplies its
  own `gap-3` actions row, and the six other header rows the previous slice
  listed as lacking the wrapper are still as they were.

### Employee detail read-first slice — CMP-03, INT-02 and NAV-03, partial

Goal: Bring `/employees/:id` to the read-first shape `/addresses/:id` and
`/users/:id` settled, calling the shared `Bilimbi.Base.UI.CommitStatus`
rather than copying it, under the captain's canonical instructions of
2026-09-20: detail pages are read-first with working in-place edit and
auto-save, an edit button is YAGNI once a page edits in place, secondary
actions are links, and Belimbing is the parity reference.

What Belimbing does, read from
`resources/core/views/livewire/admin/employees/show.blade.php` and
`app/Core/Employee/Livewire/Employees/Show.php` on 2026-09-23:

- **No edit button.** The header is the record history and a "Back to List"
  link. Full name, short name, employee number, designation, email and mobile
  number are `x-ui.edit-in-place.text`; an agent's job description is
  `x-ui.edit-in-place.textarea`.
- **Department, supervisor, employee type, status and user are
  `x-ui.edit-in-place.select`**, reading as a name or badge and saving on
  change. Company, employment start and employment end are plain text.
- **Outcomes are toasts.** `saveValidatedField` validates one field and
  notifies "Could not save changes" on refusal; each select method notifies
  its own success sentence.

Shipped:

- [x] `/employees/:id` is read-first: the "Edit employee" button is gone; the
  seven text facts are `<.inline_edit>` with `status`, the five nullable
  columns (short name, designation, email, mobile number, an agent's job
  description) pass `allow_empty` and the required full name and employee
  number do not; department, supervisor, employee type and status keep their
  click-to-select read states and report through `<.commit_status>` with the
  operator's choice named in a refusal; every outcome lands on its fact and
  success does not flash. The page calls `CommitStatus.init/1`,
  `inline_field/2`, `put/3`, `refusal_message/4`, `rejected_value/1`,
  `failure_message/0` and `write_forbidden/2` and keeps only its write, its
  nouns (`:employee_not_found`, `:company_not_found`, the orchestrator's
  protected identity) and its forbidden-flash wording. The header is the
  `flex flex-wrap items-center gap-3` row of History and "← Back" and no
  button. `{fm/employees-detail-read-first/claude-fable-5-1}`
- [x] Two domain refusals now tell the truth on the fact. Core Employee's
  update changeset trimmed text changes with `String.trim/1`, so writing
  `nil` to a nullable column raised instead of clearing it; the trim lets
  `nil` through and a blanked required column is still refused. Core User's
  `change_employee_type/4` collapsed the platform orchestrator's
  `:invariant_violation` into `:employee_not_found`, so the old page's
  orchestrator branch for that event was unreachable; the coordinator
  preserves the invariant and the fact says the identity is protected.
  `{fm/employees-detail-read-first/claude-fable-5-1}`
- [x] Web tests cover the viewer without `admin.employee.update` seeing every
  fact as plain text with no editor, trigger, select or header button; a saved
  text commit with "Saved" on the latest commit only and a cleared nullable
  fact; refused commits for format, a blanked required fact, a taken employee
  number and the orchestrator's identity, each staying on its fact until it is
  committed again; a choice committing on change, cancelling, and a forged
  choice refused with its value named; and forged writes after grant
  revocation clearing a stale "Saved".
  `{fm/employees-detail-read-first/claude-fable-5-1}`

Left read-only, deliberately:

- **Company** is a relation Core Company owns, and Belimbing shows it as text.
- **Employment start and end** are dates; `<.inline_edit>` is a text control
  and would commit an unparsed string, and Belimbing shows them as text.
- **The linked account** is the `employee.accounts` embed Core User owns, with
  its own select and notice; **subordinates** and **addresses** are their own
  workflows on this page.

Not delivered by this slice, reported as follow-up:

- **`/companies/:id`** is filed separately; the employee list and its edit
  link, the addresses panel on this page and the native `data-confirm` on the
  subordinate and delete actions are out of scope here. **Superseded
  2026-09-23:** the subordinate and delete actions confirm through
  `<.confirm_dialog>`; no `data-confirm` remains anywhere in the product.
- **`/employees/:id/edit` still exists** as a route and form; nothing on the
  detail page reaches it. Retired by the records-whose-only-page-is-a-form
  slice below.
- **INT-02 stays without a shared primitive.** The four employee choices are
  a page-local `choice_fact` shell on the same rule as the address and user
  pages; extracting one shared `<.inline_select>` waits for its control to be
  accepted.
- **The subordinates section** keeps its "Add" button, a hand-written table
  and flashes, as Belimbing's does.

### Company detail read-first slice — CMP-03 and INT-01, partial

Goal: bring `/companies/:id` to the read-first shape `/addresses/:id` and
`/users/:id` settled — facts that edit in place and save by themselves, each
reporting its own outcome through the shared commit status, with the edit
modes retired along with any button that only opened them — under the
captain's canonical instructions of 2026-09-20 applied globally.

What Belimbing does, read from
`resources/core/views/livewire/admin/companies/partials/company-details.blade.php`,
`partials/company-addresses.blade.php` and `app/Core/Company/Livewire/Companies/Show.php`
on 2026-09-23:

- **Every detail fact edits in place.** Name, code, legal name, registration
  number, tax ID, email and website are `x-ui.edit-in-place.text` (Enter or
  blur saves, Escape cancels); status, legal entity type, jurisdiction and
  parent company are `x-ui.edit-in-place.select` whose read state (a badge,
  a name, "None") is the trigger and whose select saves on change. There is
  no edit button and no modal.
- **Activities grow through a "+ Add" chip** that opens an input; Enter or
  blur adds, Escape cancels; each chip carries a hover × that removes it
  without asking.
- **Metadata opens from a pencil** beside its label into a textarea with Save
  and Cancel; Escape cancels; invalid JSON is refused with a notice.
- **The timezone is an always-visible combobox** in its own card, reading the
  company's *explicit* setting (`explicitCompanyTimezone`, or "Not
  configured"), with a saved note beside it for three seconds.
- **Every save notifies.** Belimbing reports each outcome in a toast; its
  edit-in-place components carry no per-fact status line.

Shipped:

- [x] Company Details is read-first: the "Edit Details" button and its modal
  are gone; the seven text facts are `<.inline_edit>` with `status`, name
  and code without `allow_empty` (both required) and the other five with it;
  status, legal entity type, jurisdiction and parent company are choice
  facts whose read state is the trigger, committing on change through one
  `save_choice` event and cancelling on Escape or blur; every outcome lands
  on its fact through `Bilimbi.Base.UI.CommitStatus` and success does not
  flash. The header keeps its status badge, History and "← Back" row and no
  button. `{fm/companies-detail-read-first/claude-fable-5-1}`
- [x] Business activities add through the same in-place control: a
  `placeholder` attr on `<.inline_edit>` lets an always-empty control name
  its addition ("Add activity") instead of reading as an em dash, so the
  "+ Add" flow ships without a second hook or local markup; the fact reports
  adding and removing on that control. Removal keeps its chip and its
  existing confirmation. `{fm/companies-detail-read-first/claude-fable-5-1}`
- [x] Metadata keeps Belimbing's single-fact Apply, the one place Enter cannot
  commit: the demoted pencil opens the textarea, Apply and Cancel sit under
  it, Escape cancels, a refusal ("must be a JSON object") reports on the fact
  and keeps the editor open with what was typed, and an applied empty
  document clears the value. `{fm/companies-detail-read-first/claude-fable-5-1}`
- [x] The default timezone is a choice fact of its own section, reading the
  company's explicit setting through `Settings.overridden?/2` to decide
  whether it is configured, rather than presenting the resolved value as a
  chosen one; an unset company names the zone `Bilimbi.Base.DateTime`
  renders its dates in through the tenant and platform settings — "Not
  configured (Asia/Kuala_Lumpur)" under a tenant-level zone, UTC only when
  the resolution ends there or the stored zone is unconvertible — where
  Belimbing always says UTC, which is untrue under a tenant-level setting;
  a forged zone outside the IANA database is refused on the fact. The
  always-visible select is gone; the read-state trigger is the deliberate
  Bilimbi shape recorded in DESIGN.md. `{fm/companies-detail-read-first/claude-fable-5-1}`
- [x] Every write re-asks Authz: the page's single `@write_events` gate now
  calls `Authz.can/2` per event instead of reading the mount-time assign, so
  a grant revoked while the page is open is refused, as on the other
  adopters; the capability (`admin.company.update`) and the forbidden flash
  wording are unchanged. Web tests cover a saved text commit and the header
  following it, "Saved" belonging to the latest commit only, four saved
  choices and a cancelled one, a refused email, a forged blank name, a
  truncated long value, a forged out-of-vocabulary choice, the alert
  outliving a success elsewhere, activities and metadata in place, the
  timezone fact, the revoked grant, and a viewer without
  `admin.company.update` seeing every fact with no editor.
  `{fm/companies-detail-read-first/claude-fable-5-1}`

Read-only on this page, and why:

- **Subsidiaries** are the children's own parent facts; each child edits it
  on its own page. **Departments** and **Relationships** have their Manage
  workflows. **External accesses** are relationship-scoped grants with no
  edit surface in Bilimbi. **The primary-company notice** is Core Company's
  assignment, not a company column. None of these gained an affordance.
- **Parent company** stays under `admin.company.update` as before; Belimbing
  additionally restricts assigning a non-null parent to platform admins, and
  no such guard exists in Bilimbi, so none was added.

Not delivered by this slice, reported as follow-up:

- **The departments, relationships and subsidiaries pages, and the company
  list**, keep their own affordances.
- **The chip removal's native `data-confirm`** stays as it was; whether that
  confirmation belongs on a read-first page is a separate decision.
  **Superseded 2026-09-23:** it confirms through `<.confirm_dialog>` like
  every other destructive control. Whether a read-first page should confirm a
  chip removal at all is still the open question, unchanged.
- **A shared choice-fact component.** `/addresses/:id`, `/users/:id`,
  `/employees/:id` and now `/companies/:id` each carry a private
  read-state-trigger select in the same shape; that repetition is the case for
  extracting it into Base UI, with a Design Library specimen, in its own slice.

### Records whose only page is a form — CMP-03 and NAV-03, partial

Goal: apply the captain's canonical instructions of 2026-09-20 to a record
the read-first slices passed by. An employee type has no detail page: its
routes were the list, `/employee-types/new` and `/employee-types/:id/edit`,
so the edit form was the record's page, and a rule written about detail
pages did not reach it. The rule's intent plainly does — a record's page is
read-first whether or not the codebase calls it a detail page — and
DESIGN.md's "Read-first detail pages" now says so.

What Belimbing does, read from
`app/Core/Employee/Routes/web.php`,
`app/Core/Employee/Livewire/EmployeeTypes/Edit.php` and
`resources/core/views/livewire/admin/employee-types/*.blade.php` on
2026-09-23:

- **No `show` route for a type.** `admin/employee-types/{id}/edit` is the
  record's page, under `admin.employee-type.update`: the title is "Edit
  Employee Type", the subtitle the code, the header a plain "Back" link, and
  the card holds the code as text ("Code cannot be changed."), one label
  input and a Save button. A system type aborts with 403.
- **The list's pencil** is a link to that edit page for every non-system
  row, with "System types cannot be edited" as text on the others; the
  employee list links each name to `admin/employees/{employee}` and has no
  edit link at all, because Belimbing has no employee edit route.
- **The create forms** (`employee-types/create`, `employees/create`) are
  full-width cards whose form is capped at `max-w-lg`, narrower than
  Bilimbi's `:form` width, not wider.

Shipped:

- [x] `/employee-types/:id` is the type's read-first record page
  (`Bilimbi.Core.Employee.Web.TypeShowLive`, under
  `admin.employee-type.list`), at the detail width: the code, label and kind
  on the shared `<.list>` inside a `<.section_heading>` card, the label an
  `<.inline_edit>` without `allow_empty` (the column is required) for an
  operator holding `admin.employee-type.update`, every outcome on the fact
  through `Bilimbi.Base.UI.CommitStatus`, and success does not flash. The
  code is permanent and reads as text; a system type reads as text for
  everyone with the reason beside it, and a forged write on one is refused
  on the fact. The header is the title, the code and "← Back", and no
  button; employee types are audited in neither codebase, so there is no
  history action. `{fm/records-whose-only-page-is-a-form/claude-fable-5-1}`
- [x] `/employee-types/:id/edit` is retired and `TypeFormLive` is
  create-only; the list's Edit action keeps its capability gate and glyph
  and opens the record page. A Belimbing pin to
  `/admin/employee-types/{id}/edit` remaps to `/employee-types/{id}` at
  cutover, since that page is the record's.
  `{fm/records-whose-only-page-is-a-form/claude-fable-5-1}`
- [x] `/employees/:id/edit` is retired: the employee list's Edit action
  opens `/employees/:id`, where every fact already edits in place. `FormLive`
  stays for `/employees/new`; its edit branch is unrouted code until it is
  pruned, and the module's own docs say so.
  `{fm/records-whose-only-page-is-a-form/claude-fable-5-1}`
- [x] `/users/:id/edit` is retired and the user `FormLive` is create-only;
  `/users/:id` already edits every fact in place. A Belimbing pin to
  `/admin/users/{id}/edit` remaps to `/users/{id}` at cutover. All three
  edit routes are now gone.
  `{fm/records-whose-only-page-is-a-form/claude-fable-5-1}`
- [x] The employee type list links every row's label to its record page,
  so a list-only viewer and a system type reach it; the Edit action keeps
  its capability gate and stays off system types.
  `{fm/records-whose-only-page-is-a-form/claude-fable-5-1}`
- [x] Web tests cover a viewer without the update capability seeing the
  facts and no editors (and a forged commit refused), the saved label with
  the title following it, a refused blank and an overlong value reported on
  the fact with the rejected value truncated, the alert clearing only on the
  next commit, a system type, a type outside the company, the revoked
  grant, both list Edit links and the type list's label links leading to
  the record pages, and all three retired routes unreachable through the
  router.
  `{fm/records-whose-only-page-is-a-form/claude-fable-5-1}`

Not delivered by this slice, reported as follow-up:

- **Create forms** (`/employees/new`, `/employee-types/new`) keep the `:form`
  width and their Save buttons; Belimbing's own create forms are narrower
  still (`max-w-lg`), so nothing there argues for widening.
- **The company type lists** (department types, legal entity types) already
  edit inline and were not touched.
- **The native `data-confirm`** on the list delete actions stays as it was.
  **Superseded 2026-09-23:** those deletes confirm through
  `<.confirm_dialog>`; no `data-confirm` remains anywhere in the product.
- **`FormLive`'s unrouted edit branch** is the documented drift to prune
  once the employee create form is looked at on its own.
