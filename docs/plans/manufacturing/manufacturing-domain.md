# docs/plans/manufacturing/manufacturing-domain.md

**Status:** Proposed
**Last Updated:** 2026-09-25
**Sources:**
- [`docs/plans/inventory/inventory-domain.md`](../inventory/inventory-domain.md)
- [`docs/plans/commerce-material-flow-ledger.md`](../commerce-material-flow-ledger.md)
- [`docs/plans/manufacturing/sbg-requirements.md`](sbg-requirements.md)
- [`docs/plans/domain-extension-layer-rollout.md`](../domain-extension-layer-rollout.md)
- [`docs/architecture/0010_composition-model.md`](../../architecture/0010_composition-model.md)
- [`AGENTS.md`](../../../AGENTS.md) §§4–6
- [Pull request 800](https://github.com/BelimbingApp/bilimbi/pull/800)

**Agents:** codex/gpt-5.6-luna (earlier work), codex/gpt-6-luna (this revision)

## Problem Essence

A factory cannot explain what happened when product definitions, production steps, actual work, and material records have different sources of truth. Manufacturing needs one reusable way to define and run work. Inventory/Stock remains the separate owner of material records.

- A product or route that changes in place cannot explain which instructions governed an older run.
- A planned operation is not evidence that a person or resource performed it.
- A production trace is incomplete if it creates a second material genealogy.
- Customer-specific rules in shared code make one factory's process the default for every factory.

## Desired Outcome

Manufacturing is one Domain, separate from Inventory/Stock. It begins with the Production module. Production defines products and processes, records actual work, and presents trace views over Stock genealogy.

- Product and process definitions stay distinct from records of actual work.
- Actual production inputs and outputs post through Inventory/Stock's public contract.
- Production trace adds run, step, and resource context to Stock ancestry without storing a second genealogy.
- Common process choices live as configuration data owned by Manufacturing.
- The Domain holds reusable logic; Extensions hold only customer-specific behaviour that the public contracts and Domain configuration cannot express.

## Top-Level Components

Manufacturing is a single Domain. The first module is Production; its four named capabilities below are internal boundaries, not separate selectable modules.

### Production module — first

- **Product Definition** (`product_definition`, internal) — describes what is made, referring to its Stock item and recording its formula or bill of materials and applicable revisions.
- **Process Definition** (`process_definition`, internal) — describes how it may be made through routes, logical operations, required inputs and outputs, and allowed resources.
- **Execution** (`execution`, internal) — records a production order or batch, the actual steps performed, inputs and outputs, quantities, times, people, resources, and variance.
- **Trace** (`trace`, internal read model) — answers which run, step, or resource consumed or produced a material lot by reading Inventory/Stock genealogy.

### Manufacturing-owned configuration

Process families, route templates, tolerances, output roles, process gates, and process-specific conversion bases are configuration data owned by Manufacturing. Inventory/Stock owns item-level units and conversions. Configuration extends a Domain's behaviour as data; it is not a third code layer.

### Later capability modules

Quality, Document/Change Control, Metrology/Calibration, Controlled Records, Supplier Quality, and EHS are separate later modules, not internal parts of Production. Confirm each module’s owner and public contract before it joins a Domain.

## Design Decisions

### Keep Inventory/Stock and Manufacturing as separate Domains

Each Domain has a different reason to change and a clear public contract.

- **Option A — one Commerce Domain for stock and production:** fewer boundaries at first, but warehouse use depends on production concepts and both areas share one change cycle.
- **Option B — one Manufacturing Domain with its own ledger:** production can work locally, but inventory and production develop competing balances and ancestry.
- **Option C — standalone Inventory/Stock and a separate Manufacturing Domain:** Stock owns material facts; Production calls its public contract.
- **Recommendation — Option C:** each Domain remains useful on its own and all workflows share the same material history.

### Start with one cohesive Production module

Production needs clear internal boundaries without requiring separate module releases before they solve a real problem.

- **Option A — one undivided Production implementation:** initially small, but definitions, execution, and trace become difficult to change independently.
- **Option B — make Product Definition, Process Definition, Execution, and Trace separate modules now:** ownership is explicit, but the packages and release graph are premature while one production workflow owns them together.
- **Option C — one Production module with those four internal boundaries:** keeps responsibilities clear and leaves later extraction possible if a real independent lifecycle appears.
- **Recommendation — Option C:** it gives the first module a compact boundary without turning internal names into a module registry.

### Separate definitions from actual work

A definition says what may happen. An execution records what actually happened.

- **Option A — edit definitions in place:** simple to manage, but old runs can appear to have followed today's instructions.
- **Option B — store a separate definition copy for every run:** preserves history, but duplicates the full product and route model.
- **Option C — version definitions and have each execution refer to the selected version:** preserves the instructions used and avoids copying the whole model.
- **Recommendation — Option C:** a run stays explainable when a product, formula, route, or process gate changes.

## Public Contract

The Production module gives other modules and Extensions a stable way to define and run production.

- Product Definition and Process Definition are versioned. A production order or batch selects the versions used for its execution.
- An **Operation** is a logical step in a process. A **Work Centre/Resource** is the physical machine, line, station, or capacity used for that step.
- Execution records actual inputs, outputs, quantities, location, time, operator, resource, selected definitions, and variance.
- Execution posts actual material effects through Inventory/Stock's public contract and may supply opaque execution, order or batch, and Work Centre/Resource context references.
- Production trace reads Stock's Lot/Unit Genealogy. It may add production context to a trace result but does not keep parent/child material ancestry of its own.
- Common process families and their rules are Domain-owned configuration. Customer Extensions use public contracts and may add behaviour only where configuration cannot express a confirmed need.
- Extensions do not read private Domain queries or tables. The Production module remains complete when any customer Extension is absent.
- Canonical names are Product Definition, Formula/BOM, Process Definition, Routing, Operation, Work Centre/Resource, Production Order, Batch, Execution, and Trace. Optional screen labels such as Flow, Make, Blueprint, Route, Run, and Trace do not change API or stored names.

## Phases

### Production module

#### Phase 1 — Product and process definitions

- [ ] Define versioned Product Definition and Formula/BOM contracts.
- [ ] Define versioned process routes, logical operations, inputs, outputs, and allowed resources.
- [ ] Keep process families, tolerances, output roles, and process gates as Manufacturing-owned configuration data.

Validation: an order or batch can select a specific product and route revision without relying on a customer Extension.

#### Phase 2 — Execution and Stock posting

- [ ] Record a production order or batch and its actual operation executions.
- [ ] Capture actual input, output, quantity, time, operator, resource, and variance.
- [ ] Post material effects through Inventory/Stock with optional opaque execution, order or batch, and resource references.
- [ ] Preserve which definition versions governed the recorded work.

Validation: repeated submission cannot duplicate material use, and each execution's material effects appear in the same Stock ledger as warehouse movements.

#### Phase 3 — Production trace

- [ ] Build trace as a read model over Inventory/Stock genealogy.
- [ ] Show the production runs, operations, and resources associated with material ancestry.
- [ ] Prove backward trace from output to source and forward trace from receipt to produced outputs.

Validation: trace reads Stock's ancestry and stores no second parent/child ledger.

### Later capability modules

- [ ] Define Quality only after an owner approves the inspection, result, nonconformance, or corrective-action scope.
- [ ] Define Document/Change Control only after an owner approves the controlled instruction and revision needs.
- [ ] Define Metrology/Calibration only after an owner approves the equipment and calibration evidence needs.
- [ ] Define Controlled Records only after an owner approves the retention and retrieval requirements.
- [ ] Define Supplier Quality only after an owner approves the supplier evidence and follow-up workflow.
- [ ] Define EHS only after an owner approves the safety and environmental workflow.

Validation: each later module has an explicit owner, public contract, and dependency direction before it joins a release.

The generic contracts should be checked against Mr Packaging Sdn Bhd and SBG as different factory examples; their plant rules remain in their customer requirements and Extensions.
