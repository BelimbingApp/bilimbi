# Base UI Design Library

**Status:** In progress
**Last Updated:** 2026-08-24
**Tracking:** [Issue #691](https://github.com/BelimbingApp/bilimbi/issues/691)
**Owner:** `agent:kiatng-sol-medium`

## Problem

Bilimbi's design is visible in the product, but its choices are spread across theme CSS, shared components and individual screens. Text alone cannot show whether the result feels coherent. It also cannot expose two different treatments that both look reasonable in code.

The Design Library must let a human see Bilimbi as it exists, compare contradictions and decide what becomes the design. It must not read like developer documentation or explain repository history inside the product.

## Desired Outcome

**Admin > System > Design Library** is the human review surface for Bilimbi's design.

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
5. The human records a choice using that reference.
6. A coding change removes the rejected production variation or defines the accepted context rule.
7. The same decision number moves to Design Spec as accepted design.
8. Browser review and normal project validation confirm the result before commit.

This loop is the workbench. A small project-owned agent skill may later make the audit-and-change workflow repeatable, but the skill is a tool, not another design source.

## Current Audit

The current review has seven open choices:

- `T01` — replace custom colour values with their nearest Tailwind palette steps;
- `C01` — field shape and density;
- `C02` — focus colour;
- `C03` — destructive actions;
- `C04` — filter framing;
- `C05` — table row actions; and
- `C06` — icon-control size.

These are open decisions. The page presents the live alternatives and their screen sources. It does not choose for the human.

The inventory also covers the current shared structure, navigation, tabs, buttons, form fields, multi-select, choice controls, inline editing, flash messages, alerts, badges, tables, pagination, record facts, dates, operational lists, empty states, permission states, recovery states, the Bilimbi mark and icons.

## Rules

- The Design Library is for human visual and interaction review.
- Production UI is the evidence. Old text and legacy provenance do not override what the product actually renders.
- Every public Base UI component appears in the Design Library in a meaningful state.
- A variation needing human judgment is shown, not silently normalized during the audit.
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

Validation: A human can inspect the current design, compare each open variation and answer with a short reference such as `C01 A`.

### Phase 1 — Resolve and consolidate the default design

Goal: Turn human decisions into one coherent Bilimbi default.

- [x] Record the choice for `T01`.
- [x] Record the choices for `C01`–`C06`.
- [x] Update shared components and affected screens so rejected variations no longer drift in production.
- [x] Move `T01` to Design Spec under the same number.
- [x] Move each accepted component choice to Design Spec under the same number.
- [ ] Continue the audit across the remaining application screens and add numbered decisions only where human judgment is needed.
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

- [ ] Keep reflection-based coverage for every public Base UI component.
- [ ] Add checks for local assets, contrast, focus, keyboard use, reduced motion and content security.
- [ ] Add desktop and mobile evidence for first-impression screens and representative workflows.
- [ ] Guard against raw palette use, duplicated shared markup, local component forks and unregistered icons.
- [ ] Make the Design Library skill run the same project validators used by normal development.

Validation: A new design variation is either a deliberate numbered decision or a failing drift check; it cannot hide as an unexplained local override.
