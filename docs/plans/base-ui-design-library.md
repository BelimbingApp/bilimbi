# Base UI Design Library

**Status:** Foundation merged; the parity campaign continues under Issue #709
**Last Updated:** 2026-09-17
**Tracking:** [Issue #691](https://github.com/BelimbingApp/bilimbi/issues/691)
**Agents:** `agent:kiatng-sol-medium`; `astra_pr_gate/gpt-6-astra`; `fm/parity-designlib-states/opus-5`; `fm/parity-designlib-specimens/grok-4.6`
**Related:** `docs/plans/base-ui-design-parity.md`

## Problem

Bilimbi's design is visible in the product, but its choices are spread across theme CSS, shared components and individual screens. Text alone cannot show whether the result feels coherent. It also cannot expose two different treatments that both look reasonable in code.

The Design Library must make Bilimbi's actual design visible, expose contradictions and support evidence-based acceptance. It must not read like developer documentation or explain repository history inside the product. Astra now owns routine design judgment under the user's delegation; humans can inspect the result without becoming a component-by-component approval dependency.

## Desired Outcome

**Admin > System > Design Library** is the visual and interaction review surface for Bilimbi's design.

It has two simple stages:

1. **Development review** — Theme, Components and Graphic show the current build as it really is. When Bilimbi contains different treatments for the same design problem, the page shows each treatment live, names the screens where it appears and gives the choice a stable number.
2. **Accepted design** — Design Spec records only the choices accepted for Bilimbi. An open choice does not become a rule by accident.

The current checked-out source is what Bilimbi uses. Git owns experiments, review, history and rollback. There is no Design Library database, release record, contract version, activation workflow or source metadata card.

The future default library will follow the same rule: what is checked out is what Bilimbi builds. An adopter's custom library will live in adopter-owned source. Updating Bilimbi through Git may change Bilimbi's default, but must never overwrite, regenerate or silently fill the adopter's library.

## Product Shape

Design Library is one navigation branch with four pages:

- **Theme** at `/system/design-library` — surfaces, lines, identity, feedback,
  typography, shape and density.
- **Components** at `/system/design-library/components` — numbered design decisions followed by the full shared component and pattern inventory.
- **Graphic** at `/system/design-library/graphic` — the Bilimbi mark, icons and other product graphics.
- **Design Spec** at `/system/design-library/design-spec` — accepted choices and links back to open decisions.

The pages render real production components and interactions. They do not show code examples, issue numbers, Git details, old provenance, agent instructions or internal ownership language.

## Review Loop

1. Audit the current build without assuming the current Design Library is correct.
2. List every shared design element in a live state.
3. Where different treatments exist, show them together and note the product screens where each appears.
4. Give each open choice a stable number such as `C01` and each option a letter.
5. Astra records a choice and its evidence using that reference, preserving Bilimbi identity and the user's explicit requirements.
6. A coding change removes the rejected production variation or defines the accepted context rule.
7. The same decision number moves to Design Spec as accepted design.
8. Browser review and normal project validation confirm the result before commit.

This loop is the workbench. A small project-owned agent skill may later make the audit-and-change workflow repeatable, but the skill is a tool, not another design source.

Routine design decisions do not pause for user approval. Escalate only a new business, security or durable data-contract decision outside the accepted scope. The parity plan owns the detailed autonomous workflow and slice boundaries.

## Current Audit

`T01` and `C01`–`C06` were resolved in the merged foundation, implemented in production UI and moved to Design Spec. Root guidance and the parity baseline now preserve those decisions and the intentional content-sized pagination correction from #304. The subsequent #694 integration preserves 24px inline icon targets through the shared component, with table/toolbar controls still 28px, and retains status-first company actions and the pin-state regression test.

The inventory also covers the current shared structure, navigation, tabs, buttons, form fields, multi-select, choice controls, inline editing, flash messages, alerts, badges, tables, pagination, record facts, dates, operational lists, empty states, permission states, recovery states, the Bilimbi mark and icons.

The Navigation entry renders `Layouts.nav_branch/1`, the shell's own rail, over an example tree rather than a second definition of it. The shell's nav rules moved from the `#app-sidebar` id to an `.app-nav-rail` class that the sidebar and the library card both carry, so the card cannot drift in type scale, colour, icon suppression or caret direction without the sidebar drifting with it. The card omits the pin control: the shell resolves a pinned row only from the sidebar, so a pin anywhere else is a control that looks live and does nothing. Tabs and radio group are shared `Bilimbi.Base.UI.Components` entries: Schedule uses `<.tabs>` for its Tasks / History / Settings views and Settings uses it for its group strip, so neither is library-only markup.

Appearance Settings is the one screen `<.radio_group>` does not describe. It puts each theme choice in a bordered card with a description, which the component does not express, and converting it would redesign that screen. The radio group entry says so on the page, as the Navigation card names the pin control it leaves out and the branch toggle that renders without collapsing outside the sidebar.

## Rules

- The Design Library supports visual and interaction review by Astra and product reviewers.
- Production UI is the evidence. Old text and legacy provenance do not override what the product actually renders.
- Every public Base UI component appears in the Design Library in a meaningful state.
- Variations are inspected and resolved by Astra with recorded evidence and recognizable use cases.
- Source notes name recognisable product screens and routes.
- Accepted decisions retain their review number so the decision can be traced without exposing development history in normal UI.
- Feature screens use Base UI semantic meaning rather than library identity, raw palette or private asset paths.
- A design change cannot change authorization, tenancy, business rules, durable data meaning or the truth of feedback.
- `/system/design-library` is the canonical name. There is no `/system/ui-reference` alias.
- Bilimbi replaces Belimbing in one direction. New Bilimbi design capabilities do not need old internal names or a reverse compatibility path.

## Initial Boundaries

The first implementation is read-only with respect to design source. It shows the authenticated shell, visual foundations, shared components, common patterns, important states and local graphics.

Do not initially build an in-browser editor, embedded AI, database drafts, library releases, runtime library installation, a marketplace, per-tenant selection or visual page composition.

## Phases

### Phase 0 — Current design review

Goal: Make the current Bilimbi design visible and decidable.

- [x] Rename UI Reference to Design Library across routes, menu, capability, LiveViews and tests.
- [x] Split Design Library into Theme, Components, Graphic and Design Spec.
- [x] Remove library identity, contract version and source metadata from the implementation and UI.
- [x] Rewrite the UI for a human product reviewer.
- [x] Audit the current build and present the first six conflicting treatments as numbered decisions with screen sources.
- [x] Present the shared component, pattern, state, mark and icon inventory using production UI.
- [x] Separate accepted design from open decisions.
- [x] Complete focused tests and desktop/mobile browser review.
- [x] Record the implementation evidence on issue #691.

Validation: A reviewer can inspect the current design and compare each variation using stable references such as `C01 A`.

### Foundation closeout — Issue #691 / https://github.com/BelimbingApp/bilimbi/pull/696

Goal: Merge a verified Design Library foundation before beginning the parity campaign.

- [x] Integrate current `main` through `d105ebe` without destructive history rewriting. `{astra_pr_gate/gpt-6-astra}`
- [x] Reconcile the later `d93feb1` merge with the shared icon component, preserving #694 behavior and updating the inline target size in Design Spec and guidance. `{astra_pr_gate/gpt-6-astra}`
- [x] Give both pagination specimens independent in-memory results, working page and page-size controls, bounded pages and honest summaries. `{astra_pr_gate/gpt-6-astra}`
- [x] Make the composite example search filter its own rows and recover from empty results. `{astra_pr_gate/gpt-6-astra}`
- [x] Replace fabricated company navigation with local example previews. `{astra_pr_gate/gpt-6-astra}`
- [x] Reconcile pagination geometry and delegate routine parity acceptance to Astra. `{astra_pr_gate/gpt-6-astra}`
- [x] Complete focused interaction tests, formatting, browser review of all four routes and full `mix precommit` for the foundation closeout. `{astra_pr_gate/gpt-6-astra}`

Final closeout evidence: after integrating #694, `mix precommit` completed with 1,393 passing tests, including 538 Web tests, and six installed contribution snapshots verified. Focused shell/company/Design Library verification passed 79 tests; shared button verification passed seven tests. Asset build, `mix format --check-formatted`, the repository's deterministic mandates, focused strict Credo with CI's configured exclusions and `git diff --check` passed. Browser review covered Theme, Components, Graphic and Design Spec at 1440×900 and 390×844 in light and dark themes. It verified independent pagination, keyboard page changes, empty-search recovery, visible example-only feedback, contained table overflow and an unclipped three-digit page-size selector. Focused browser rechecks after the latest integration confirmed 24×24 inline and sidebar pin/unpin targets, 28×28 table actions and the company status-first action row. The development account's original dark theme and the browser viewport were restored after review.

- [x] Repeat relevant verification after integrating #694, including shared icon sizing, shell pin-state behavior and full `mix precommit`. `{astra_pr_gate/gpt-6-astra}`

The foundation merged at https://github.com/BelimbingApp/bilimbi/pull/696 on 2026-09-14 at 07:02:16 UTC with all seven checks passing.

The shell account menu, top-bar timezone/theme controls and icon parity are recorded requirements for the next slice. The wider parity campaign, optional inspection skill and adopter-owned library are follow-up work and do not block this foundation's closeout.

### Phase 1 — Resolve and consolidate the default design

Goal: Turn accepted decisions into one coherent Bilimbi default.

- [x] Record the choice for `T01`.
- [x] Record the choices for `C01`–`C06`.
- [x] Update shared components and affected screens so rejected variations no longer drift in production.
- [x] Move `T01` to Design Spec under the same number.
- [x] Move each accepted component choice to Design Spec under the same number.
- [x] Issue #720 — give the components shown in only one presentation their real states: the three page widths as live page calls on one wide stage, a header whose action sits beside the title, cards with and without a title, an error flash under the info flash, and the outline, solid and mini icon treatments each drawn at its own natural size, above a separate pair showing that size and colour are chosen where the icon is used. Where the component has no further state — card, record facts and icon — the specimen says so instead of inventing one. `{fm/parity-designlib-states/opus-5}`
- [x] Replace the Design Library's fake Navigation, Tabs, and Radio group specimens with the real rail and shared Base UI components, and adopt tabs on the Schedule board and the Settings group strip. `{fm/parity-designlib-specimens/grok-4.6}`
- [ ] Complete the approved catalog and parity campaign in `docs/plans/base-ui-design-parity.md`; that plan owns the detailed IDs, agent lanes and acceptance evidence.
- [ ] Give each changeable design fact one owner in the smallest useful default-library structure.
- [ ] Create a small Design Library agent skill for inspection, focused edits, browser review and validation.

Validation: The accepted default design is reproduced by the production UI, and the Design Library no longer shows resolved options as if both remain valid.

### Phase 2 — Drop-in adopter library

Goal: Let an adopter bring its own brand without losing it during a Bilimbi update.

- [ ] Separate Bilimbi's upstream-owned default from adopter-owned custom library source.
- [ ] Build one deliberately different complete custom library as proof.
- [ ] Select exactly one checked-out library per installation without runtime release state.
- [ ] Prove the custom library changes authentication, shell, components and representative screens without feature-module edits.
- [ ] Prove a Git update changes the Bilimbi default while leaving adopter files unchanged.
- [ ] Fail clearly when an adopter library no longer satisfies a required design shape; never silently fill from the default.

Validation: Updating Bilimbi does not modify the adopter's design, and the running product never mixes an adopter library with a moving default.

### Phase 3 — Drift prevention

Goal: Let Bilimbi evolve quickly while making inconsistency visible.

Drift guards are inventoried only in `docs/plans/base-ui-design-parity.md` Phase 6, which owns campaign execution detail; this plan does not keep a second list. As of 2026-09-17 that phase records two guards built by https://github.com/BelimbingApp/bilimbi/pull/722 — reflection-based coverage of every public Base UI component in its declared states, and rejection of hand-written markup that imitates a shared component — both tagged `:design_library_drift` and excluded from the default test run and `mix precommit` until the specimens they report are corrected. Guards for raw palette use, local component forks in production screens and unregistered icons remain open there.

- [ ] Add checks for local assets, contrast, focus, keyboard use, reduced motion and content security.
- [ ] Add desktop and mobile evidence for first-impression screens and representative workflows.
- [ ] Make the Design Library skill run the same project validators used by normal development.

Validation: A new design variation is either a deliberate numbered decision or a failing drift check; it cannot hide as an unexplained local override.
