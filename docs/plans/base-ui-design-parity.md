# Base UI Design Parity

**Status:** In progress — application shell implemented and validated; independent review pending for Issue #710
**Last Updated:** 2026-09-14
**Sources:** `docs/plans/base-ui-design-library.md`; `DESIGN.md`; root `AGENTS.md`; Issue #691; https://github.com/BelimbingApp/bilimbi/pull/696 (merged); [campaign #709](https://github.com/BelimbingApp/bilimbi/issues/709); [shell #710](https://github.com/BelimbingApp/bilimbi/issues/710); `apps/base/ui/`; `apps/web/assets/css/app.css`; Belimbing `UiReferenceSection`, UI Reference partials, shared UI components, `tokens.css`, and `components.css`
**Agents:** `crewmate/gpt-6` (`agent:kiatng-sol-medium`); `astra_pr_gate/gpt-6-astra` (autonomous design steward)

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
| NAV-02 | Tabs | Example markup only | Provide shared semantics, keyboard navigation, active state and URL/history rules. |
| NAV-03 | Link dictionary and related-link groups | No shared contract | Adopt internal, anchor, external, new-tab and download behavior; mutations remain buttons. |
| NAV-04 | Pagination | Shared component exists | Compare narrow layout, disabled states, page-size control, URL state and accessible labels. |
| NAV-05 | User account and scope menu | Partial user footer exists | On user-circle activation, show signed-in name and identifier, current company and tenant, change password and sign out. Show scope switching only when more than one permitted scope exists. |
| ACT-01 | Buttons | Primary, secondary and destructive basics | Cover emphasis, compact size, disabled, loading, navigation and truthful completion. |
| ACT-02 | Icon actions and groups | Basic icon button exists | Add grouping, context sizing, disabled/loading behavior and accessible tooltips. |
| ACT-03 | Destructive entry and acknowledgement | Inconsistent screen patterns | Standardize consequence copy, confirmation and typed acknowledgement where risk requires it. |
| INP-01 | Shared field shell | Generic input has labels, hints and errors | Standardize required, help, error, disabled, read-only, prefix and suffix placement. |
| INP-02 | Text, email, URL, telephone, number and textarea | Available through the generic input | Complete state and sizing contracts and validate realistic long content. |
| INP-03 | Search | Generic search type | Add clear, empty, loading and result-update behavior. |
| INP-04 | Select, multi-select, checkbox and radio | Partial shared coverage | Complete open/close, summary, no-options, outside-click, Escape and keyboard behavior. |
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
- The top bar exposes the current timezone and light/dark theme selectors. A change applies immediately, persists for the signed-in user and truthfully affects subsequent date/time or theme rendering.
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
- [ ] Verify every catalog row against the current Bilimbi build and Belimbing reference.
- [ ] Give each row its initial disposition and dependency without treating component existence as acceptance.
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
| Top-bar timezone | Adopt adapted | Belimbing's Company/Local/Stored choices and clock meaning are useful. Bilimbi uses the existing Base DateTime preference contract and updates mounted and streamed timestamps in place after a confirmed save. Explicit per-element display and calendar dates remain independent. |
| Top-bar theme | Adopt adapted | Preserve Light/Dark/System as three explicit choices. Existing Core User preference storage remains authoritative. System follows browser appearance; failed writes retain the saved choice and provide recovery feedback. |
| FND-06 shell icons | Equivalent | Clock, sun, moon, computer desktop, navigation bars and password key use familiar meanings through `IconRegistry.shell/1`. The existing Bilimbi navigation registry and impersonation icon remain in use. The wider searchable icon catalog is outside this slice. |
| FND-06 logout exception | Keep Bilimbi | Keep the existing rightward sign-out arrow meaning and label it “Sign out”; no Belimbing icon asset is copied. |

Implementation and adoption: `Bilimbi.Base.UI.ShellComponents` supplies the account disclosure, access warning and display controls to `Layouts.app`. The authenticated Web hook resolves fresh session identity before preference writes and uses the existing User and DateTime APIs; no schema or preference-key migration was needed. An impersonated session writes no display preference: the shell replaces the controls with the active time display and says why, and the hook refuses the write. Every authenticated route adopts the shell, with direct browser checks on `/dashboard`, `/companies`, `/settings/password` and all four Design Library routes. `/system/design-library/components#component-shell` renders the real controls, a live timestamp and an account-action specimen with truthful example feedback. `/system/design-library/design-spec#spec-shell` records the accepted user behavior.

Validation evidence:

- `mix precommit` passed on 2026-09-14: all Base/Core suites, 547 Web integration tests and six installed contribution snapshots. `mix format --check-formatted` and `git diff --check` passed. Meaningful coverage includes revoked-session rejection, per-user isolation, remount persistence, invalid input and failed HTTP writes, ordinary/operator/impersonated warnings, duplicate-work prevention, disconnect/unknown-result feedback, and timestamp updates including explicit overrides and newly mounted rows.
- Browser inspection used isolated `chrome-devtools-axi` sessions against shared Bilimbi at port 4000, the read-only Belimbing dashboard, and this branch's preview at port 4017. Reference source inspected: `resources/core/views/components/layouts/top-bar.blade.php` and sidebar components. Belimbing's timezone menu supports Company/Local/Stored with outside/Escape dismissal; theme icons are clock/sun/moon/computer-desktop. Its timezone save reloads the page and failed requests lack the explicit retry feedback implemented here. Reference appearance was changed only in page-local DOM for visual inspection; no reference preference writes were made.
- Real pointer and keyboard input verified account open/close, password navigation, sign out and fresh sign-in. Escape returns account focus to the circle; a second Escape closes the narrow drawer and returns focus to the sidebar toggle. Forward/reverse Tab contain focus inside the drawer. Desktop expanded and 56px collapsed rail, 390×844 narrow layout, light and dark themes were inspected. Narrow shell and library have no document-level horizontal overflow. Existing operational table scrolling remains local to its workflow.
- Actual timezone saves changed existing dashboard timestamps immediately between UTC and Asia/Kuala_Lumpur device time. The library timestamp also followed its own real display control. A deliberately invalid browser-side choice was rejected by the server, kept the previous theme selected and exposed “Could not save display preference…”; retry then succeeded. System theme followed light/dark media changes without a preference write. Fresh sign-in restored the saved theme and timezone mode.
- The shared development database was not provisioned with extra scopes, per the clarified scope decision. The test account's original dark/company preferences were restored. The shared port-4000 process and configuration were not changed; port 4017 is the isolated worktree preview.

Checked visual evidence: [expanded production shell, light](evidence/base-ui-shell/companies-expanded-light.png), [narrow account drawer, dark](evidence/base-ui-shell/narrow-account-dark-final.png), [live library disclosure, dark](evidence/base-ui-shell/library-shell-dark-final.png), [narrow library, light](evidence/base-ui-shell/library-narrow-light-final.png). Screenshots supplement the exercised controls and tests; they are not the interaction evidence by themselves.

Delivery: https://github.com/BelimbingApp/bilimbi/pull/711 is the bounded draft for #710. Independent review and the Firstmate-directed no-mistakes shipping gate remain pending; this implementation does not claim those gates passed. Later catalog families, broad production-screen migration, searchable icon parity and drift guards remain open in the campaign phases above.
