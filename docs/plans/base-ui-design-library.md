# Base UI Design Library

**Status:** Proposed
**Last Updated:** 2026-08-24
**Sources:** Issue #689; Root `AGENTS.md`; `DESIGN.md`; `docs/plans/AGENTS.md`; ADR 0002; `docs/architecture/0010_composition-model.md`; ADR 0004; `apps/base/ui/`; `apps/web/assets/css/app.css`; existing Base UI reference implementation; `.design_library/bilimbi/` generated TraeWork export; visual inspection of TraeWork's custom and built-in Design Library on 2026-08-23
**Agents:** codex/gpt-5.6-sol

## Problem Essence

Bilimbi's design is spread across text guidance, theme CSS, Base UI components, application screens, and a live UI Reference. A human cannot validate the experience from text, while AI coding agents can interpret the same guidance differently and preserve old decisions as the design evolves.

Bilimbi needs a fast loop in which a human sees and uses the real design, asks an agent to change it, and immediately validates the result. The resulting design must remain portable and must let Bilimbi evolve through Git without overwriting an adopter's custom brand.

## Desired Outcome

The checked-out Design Library files are the design Bilimbi uses and the single source of truth for changeable design facts. A project-owned agent skill acts as the design workbench: it helps a coding agent understand, change, inspect, and validate the library. **Admin > System > Design Library** renders those same files through real production components so a human can review the design and interactions.

Git provides experiments, history, review, approval and rollback. Bilimbi does not add another draft, release, versioning or activation system.

Bilimbi ships a default library. An adopter keeps a complete custom library in adopter-owned source and configures Bilimbi to use it. Updating Bilimbi through Git may change the platform, design contract and default library, but it never changes the adopter library. An incompatible custom library fails validation and requires an explicit adopter change; Bilimbi never fills it with new defaults or silently replaces it.

The product principle is: the adopter owns the brand; Bilimbi owns semantic truth and interaction integrity.

## Top-Level Components

### Design Library Files

The library is a Git-owned source directory containing the design Bilimbi compiles: its identity, contract compatibility, foundations, graphics, component presentation, patterns, flows and design specifications. The exact file layout should be the smallest shape proven by the default library and one contrasting custom library.

The current files are current truth. A library has a stable `library_id` and `contract_version`, but no separately maintained release version. A fingerprint may be generated for build caching and diagnostics; humans do not edit it. The Git commit identifies the exact historical state.

The default library and every adopter library are complete and independent. An adopter may copy the default as a starting point, but the copy receives a new identity and does not inherit live values from the moving default.

### Design Library Agent Skill

The project-owned skill is the workbench for AI coding agents. It tells an agent how to:

- locate the selected library and its contract;
- understand the visual and interaction intent;
- inspect the live Design Library page;
- change the library rather than scatter local screen overrides;
- run focused validation;
- review affected components, patterns, flows and first-impression screens; and
- report what changed and what still needs human judgment.

The skill may use small deterministic scripts for discovery, validation and context assembly. It is a tool that changes the source of truth; it is not itself the source of truth and Bilimbi does not depend on a particular AI model at runtime.

### Admin > System > Design Library

The existing UI Reference implementation becomes the visual and interactive projection of the selected library. Reuse its production component rendering, route contribution, authorization and reflection-based component coverage instead of building a parallel area. Rename the route, navigation identity, authorization capability, LiveView, tests and page consistently around **Design Library**. The canonical route is `/system/design-library`; do not keep `/system/ui-reference` as an alias.

The page is read-only with respect to design source. It allows a human to interact with components and review:

- Foundations: semantic colors, typography, spacing, size, radius, density, borders and motion.
- Components: real variants, states, focus, keyboard behaviour and pending work.
- Patterns: navigation, page structure, forms, filters, tables, empty states and feedback.
- Flows: login, password recovery, dashboard arrival, operational work, permission denial, failure and recovery.
- Graphics: logos, product marks, icons and locally bundled assets.
- Specifications: intent, usage, accessibility, source ownership and prohibited variations.

Useful controls include supported themes, realistic short and long content, interactive states, reduced motion, and desktop/mobile examples. The page shows the selected library ID, contract version and generated fingerprint so the human and agent know which source they are reviewing.

The Design Library page is itself important UI. It uses the selected library and must meet the same design, interaction and accessibility standards as the rest of Bilimbi.

### Base UI and Web Integration

Base UI owns the stable semantic component and interaction contract. Feature modules express meanings such as primary action, destructive action, status, selection, loading, failure and recovery through Base UI; they do not depend on a library ID, raw palette, library asset path or private implementation detail.

Web owns the host asset build and delivery needed by the selected library. Library validation happens before a build or deployment can succeed. Bilimbi loads no arbitrary remote CSS, JavaScript or templates at runtime.

### Human and Agent Loop

The working loop is deliberately small:

1. The human asks a separate coding agent to explore or change part of the design.
2. The agent uses the Design Library skill and edits the selected library on the current Git branch.
3. **Admin > System > Design Library** renders the changed files through production UI.
4. The human interacts with the result and gives further direction.
5. The agent validates the library and affected application screens.
6. The accepted design is committed and deployed through the normal Git workflow.

## Design Decisions

### Files are the authority

The checked-out Design Library is the only authority for changeable design facts. The admin page is its visual projection, the agent skill is its editing workflow, and production UI is its execution. `DESIGN.md` and `AGENTS.md` retain enduring intent, ownership and hard rules without repeating volatile library values.

### Git is the lifecycle

Branches and working trees hold experiments, commits hold accepted states, diffs show changes, and revert provides rollback. There is no Design Library database, draft registry, datetime release version, activation workflow or previous-release store.

### One selected library per installation

Bilimbi selects one trusted library from the checked-out source during build. The default is used only when no adopter library is configured. Per-tenant selection, runtime installation and a library marketplace are outside the initial architecture.

### The page validates; the skill changes

**Admin > System > Design Library** remains focused on seeing and using the design. Design source changes happen through coding agents using the skill and normal repository tools. Bilimbi does not build an embedded AI agent or visual design editor.

### Libraries are platform design inputs

A Design Library is governed by Base UI. It is not a Domain, Extension or merged module contribution. This keeps one coherent product design and follows the composition principle that a company selects trusted source and compiles its own application.

### Belimbing compatibility is one direction

The Design Library is a Bilimbi-native capability and does not need a Belimbing counterpart. Bilimbi compatibility means Bilimbi can adopt and replace Belimbing while preserving required durable data and business meaning. It does not require Belimbing to consume Bilimbi features or Bilimbi to preserve legacy internal UI and route names. New Bilimbi concepts use truthful Bilimbi names from the beginning.

## Public Contract

- The selected, checked-out Design Library files are what Bilimbi compiles and renders.
- A library declares a stable ID and contract version. Git owns historical versioning; an optional fingerprint is generated from content.
- Exactly one complete library is selected for an installation.
- A configured but missing, incomplete, unsafe or incompatible library fails before deployment. Bilimbi does not silently fall back to the default.
- The supported source layout keeps Bilimbi's upstream-owned default separate from adopter-owned custom libraries.
- A Git update may change Bilimbi's default and design contract but never writes to, merges into, regenerates, resets or replaces an adopter library.
- An adopter library does not inherit unresolved values from the default. Adopting a new default decision is an explicit Git change owned by the adopter.
- Feature modules use Base UI semantic APIs and remain independent of the selected library.
- A library may change presentation and approved interaction design, but it cannot change authorization, tenancy, business rules, durable data meaning or the truth of user feedback.
- Status, action, brand, selection, focus and neutral information remain distinct semantic roles.
- Library fonts, styles, icons and graphics are local, licensed, bundled and compatible with Bilimbi's content-security rules.
- The Design Library page renders production components and behaviour, not screenshots or separately reconstructed examples.
- The Design Library page and its route use the canonical `design-library` name throughout; no `ui-reference` compatibility alias remains.
- The agent skill reads and changes library source but does not become a second design specification.
- The generated `.design_library/bilimbi/` TraeWork export remains research evidence only; Bilimbi does not adopt its format or require TraeWork.

## Initial Boundaries

The first implementation covers the browser product: unauthenticated entry, authenticated shell, Base UI components, shared patterns, critical flows, responsive examples, supported themes and locally served graphics.

Do not initially build per-tenant libraries, runtime library installation, a marketplace, an in-browser editor, an embedded AI agent, database-managed drafts, release management, visual page composition, or branded email and document rendering.

## Phases

### Phase 0 — Usable design loop

Goal: Give the human and a coding agent a complete see-change-review loop before expanding the library architecture.

- [ ] Establish the minimum default-library identity and contract needed to describe the current Bilimbi design without intentionally changing it.
- [ ] Rename the existing reference route, navigation identity, authorization capability, LiveView, templates and tests consistently to **Design Library**, with `/system/design-library` as the only route and no compatibility alias.
- [ ] Organise the page into Foundations, Components, Patterns, Flows, Graphics and Specifications while continuing to render real Base UI code.
- [ ] Cover current public components, their meaningful interactive states and the first-impression flows needed to judge trust in Bilimbi.
- [ ] Show the selected library ID, contract version and generated fingerprint.
- [ ] Create the first project-owned Design Library agent skill with instructions for inspection, focused edits, browser review and validation.
- [ ] Prove one complete iteration: human direction, agent library change, live visual review, correction, validation and Git commit.

Validation: A human can ask a separate coding agent for a design change, refresh the Design Library page, interact with the real result and decide whether it is right.

### Phase 1 — Consolidate the default library

Goal: Move changeable design facts behind one library boundary while preserving the reviewed Bilimbi experience.

- [ ] Inventory current facts across `DESIGN.md`, root `AGENTS.md`, Base UI, Web theme CSS, application screens, graphics and UI Reference prose; give each fact one owner.
- [ ] Consolidate foundations, graphics, component presentation, patterns, flows and specifications into the smallest coherent default-library structure.
- [ ] Resolve contradictions through human review on the Design Library page rather than choosing between stale prose and code silently.
- [ ] Keep Base UI's semantic API stable and remove library-specific decisions from feature modules.
- [ ] Add deterministic library discovery, contract validation and fingerprint generation without creating runtime registry state.
- [ ] Move volatile values out of `DESIGN.md` and `AGENTS.md` only after their library authority and visual projection are working.

Validation: The default library reproduces the approved design, and changing one library fact reaches every conforming preview and screen without manual duplication.

### Phase 2 — Drop-in adopter library

Goal: Prove that an adopter can own a distinct brand and continue updating Bilimbi through Git.

- [ ] Define a non-overlapping Git ownership layout for the upstream default, adopter libraries and installation selection.
- [ ] Create one deliberately contrasting custom library as contract evidence, not as another Bilimbi default.
- [ ] Prove the custom library changes the recognisable brand across authentication, shell, components, representative screens and first-impression flows without feature-module edits.
- [ ] Prove that a representative Bilimbi Git update can change the default while leaving custom-library files and fingerprint unchanged.
- [ ] Make an incompatible custom library fail with precise migration guidance before build or deployment; never fill missing design facts from the default.
- [ ] Document how an adopter explicitly takes a desired newer default decision into its own library through a normal reviewed Git change.

Validation: Bilimbi renders the selected custom library coherently, and updating upstream Bilimbi neither changes it nor silently falls back to the default.

### Phase 3 — Conformance and drift prevention

Goal: Let design evolve quickly while making local bypasses and broken experiences visible.

- [ ] Validate library completeness, compatibility, local assets, licensing, contrast, focus, keyboard behaviour, reduced motion and content security.
- [ ] Retain and strengthen reflection-based coverage so every public Base UI component appears on the Design Library page.
- [ ] Add production-backed visual evidence for first-impression flows, representative components, patterns, themes and desktop/mobile examples.
- [ ] Test pending work, duplicate rejection, truthful outcomes, failure, recovery and reconnect behaviour.
- [ ] Guard against raw palette use, library-specific classes or assets in feature modules, duplicated shared markup and unregistered icons.
- [ ] Make the agent skill run the same validators used by normal project verification rather than implementing weaker parallel checks.

Validation: A deliberate design bypass or incomplete library fails with useful provenance, while an approved library change propagates through the shared system.

### Phase 4 — Documentation and adoption

Goal: Contributors and adopters can use the design loop without reviving parallel sources of truth.

- [ ] Rewrite `DESIGN.md` around enduring intent and navigation to the live Design Library rather than resolved values.
- [ ] Update root and scoped `AGENTS.md` guidance to require the Design Library skill, Base UI semantic APIs and visual validation.
- [ ] Document library creation, selection, validation, Git update, explicit custom-library migration and failure recovery.
- [ ] Document ownership across Base UI, Web asset integration, feature modules and adopter source.
- [ ] Migrate remaining product screens to conforming components and patterns, recording genuine temporary exceptions with owners.
- [ ] Revisit deferred runtime or tenant-specific capabilities only when a real adopter requirement justifies them.

Validation: A new contributor can use the skill, inspect the live Design Library, change a representative design object and verify the result without consulting another manually synchronised design specification.
