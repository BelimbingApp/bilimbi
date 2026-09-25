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
- [Pull request 804](https://github.com/BelimbingApp/bilimbi/pull/804)

**Agents:** codex/gpt-5.6-luna (earlier work),
codex/gpt-6-luna-xhigh (this revision),
claude/claude-opus-5.5 (no-mistakes review agent)

## Problem Essence

A factory cannot explain what happened when product definitions, production steps, actual work, and material records have different sources of truth. Manufacturing needs one reusable way to define and run work. Inventory/Stock remains the separate owner of material records.

- A product or route that changes in place cannot explain which instructions governed an older run.
- A planned operation is not evidence that a person or resource performed it.
- A production trace is incomplete if it creates a second material genealogy.
- Customer-specific rules in shared code make one factory's process the default for every factory.

## Desired Outcome

Manufacturing is one Domain, separate from Inventory/Stock, organised as the modules a manufacturing ERP would expect. It starts with the two modules every factory needs to define and run work; planning, maintenance, and costing join when a real need proves them.

- Product and process definitions stay distinct from records of actual work.
- Actual production inputs and outputs post through Inventory/Stock's public contract as its registered production posting authority.
- Under-cured or otherwise held material cannot be consumed without an authorised, recorded override.
- Production trace adds run, step, and resource context to Stock ancestry without storing a second genealogy.
- Common process choices live as configuration data owned by Manufacturing.
- The Domain holds reusable logic; Extensions hold only customer-specific behaviour that the public contracts and Domain configuration cannot express.

## Top-Level Components

Manufacturing is a single Domain made of selectable modules. It knows nothing about any one customer.

### Modules

- **Product Definition** (`product_definition`) — **first.** Says what is made and how: links to Stock items, versioned BOM/recipe, routings with their operations, and work-centre definitions. It also holds process configuration such as process families, tolerances, output roles, and hold rules like a cure minimum.
- **Production Execution** (`production_execution`) — **first.** Runs production orders and their operations, and posts consumption and output through Stock's registered posting-authority seam. It enforces the cure hold and owns the trace read model over Stock genealogy.
- **Planning** (`planning`) — **later.** Master production schedule, material requirements planning (MRP), and capacity. It waits until a customer needs a shared schedule or MRP; customer-specific planning stays in that customer's Extension until then.
- **Maintenance** (`maintenance`) — **later.** Equipment records and preventive maintenance for work centres. It waits until an owner confirms the equipment and downtime workflow.
- **Costing** (`costing`) — **later.** Standard and actual production cost and their variance, read from Stock transactions and execution records. It waits until an owner confirms valuation rules; Stock reserves "Material Ledger" for that valuation.

### Neighbouring Domains

- **Inventory/Stock** — owns items, units, the Material Transaction ledger, and Lot/Unit Genealogy. See [`inventory-domain.md`](../inventory/inventory-domain.md).
- **Quality** — owns inspection, nonconformance, corrective action, and is the future home of QAC. It is a separate capability Domain because its lifecycle is industry-wide and it works without Manufacturing. Manufacturing links to Quality records through Quality's public contract.
- **Other later capability Domains** — Document/Change Control, Metrology/Calibration, Controlled Records, Supplier Quality, and EHS sit beside Manufacturing, not inside it.

Configuration extends a module's behaviour as data; it is not a third code layer. Inventory/Stock owns item-level units and conversions; Product Definition owns process-specific conversion bases.

## Design Decisions

### Keep Inventory/Stock and Manufacturing as separate Domains

Each Domain has a different reason to change and a clear public contract.

- **Option A — one Commerce Domain for stock and production:** fewer boundaries at first, but warehouse use depends on production concepts and both areas share one change cycle.
- **Option B — one Manufacturing Domain with its own ledger:** production can work locally, but inventory and production develop competing balances and ancestry.
- **Option C — standalone Inventory/Stock and a separate Manufacturing Domain:** Stock owns material facts; Production Execution posts through its public contract.
- **Recommendation — Option C:** each Domain remains useful on its own and all workflows share the same material history.

### Map the Domain top-down, build two modules first

Readers and later agents need the whole Manufacturing map, but only proven modules should be built.

- **Option A — one Production module with internal boundaries:** compact at first, but hides where planning, maintenance, and costing belong.
- **Option B — build every ERP module now:** complete on paper, but invents planning, maintenance, and costing rules no customer has confirmed.
- **Option C — name every module now, build Product Definition and Production Execution first:** the map is clear, and later modules arrive with a real owner and contract.
- **Recommendation — Option C:** it answers where each capability lives without building speculative modules.

### Separate definitions from actual work

A definition says what may happen. An execution records what actually happened.

- **Option A — edit definitions in place:** simple to manage, but old runs can appear to have followed today's instructions.
- **Option B — store a separate definition copy for every run:** preserves history, but duplicates the full product and route model.
- **Option C — version definitions and have each execution refer to the selected version:** preserves the instructions used and avoids copying the whole model.
- **Recommendation — Option C:** a run stays explainable when a product, formula, route, or hold rule changes.

## Public Contract

Product Definition and Production Execution give other modules and Extensions a stable way to define and run production.

- Product Definition is versioned. A production order selects the BOM/recipe and routing versions used for its execution.
- An **Operation** is a logical step in a routing. A **Work Centre/Resource** is the physical machine, line, station, or capacity used for that step.
- Execution records actual inputs, outputs, quantities, location, time, operator, resource, selected definitions, and variance.
- Warehouse receipts and ordinary warehouse movements post directly to Inventory/Stock. Production commands and production or AX-history imports enter Production Execution's public execution/import contract, which validates the operation and posts Stock effects with opaque context references.
- Production Execution registers itself at boot as Stock's production posting authority. Stock refuses production or transform postings from anyone else, so an Extension cannot bypass Manufacturing's validation.
- Execution completion, Stock effects, and any required override evidence succeed or fail together.
- Consumption of material under a configured hold, such as a cure minimum, is refused by default. An override needs an explicit Base Authz capability and a mandatory reason, and records actor, time, reason, and affected unit as an immutable record.
- Production trace reads Stock's Lot/Unit Genealogy. It may add production context to a trace result but does not keep parent/child material ancestry of its own.
- Common process families and their rules are Domain-owned configuration. Customer Extensions use public contracts and may add behaviour only where configuration cannot express a confirmed need.
- Extensions do not read private Domain queries or tables. Each module remains complete when any customer Extension is absent.
- Canonical names are Product Definition, Formula/BOM, Routing, Operation, Work Centre/Resource, Production Order, Batch, Execution, and Trace. Optional screen labels such as Flow, Make, Blueprint, Route, Run, and Trace do not change API or stored names.

## Phases

### Product Definition module

#### Phase 1 — Products, BOMs, and routings

- [ ] Link product definitions to Stock items and define versioned Formula/BOM contracts.
- [ ] Define versioned routings, logical operations, inputs, outputs, and allowed work centres/resources.
- [ ] Keep process families, tolerances, output roles, and hold rules such as a cure minimum as configuration data.

Validation: an order can select a specific product and routing revision without relying on a customer Extension.

### Production Execution module

#### Phase 1 — Orders, execution, and Stock posting

- [ ] Record a production order or batch and its actual operation executions.
- [ ] Capture actual input, output, quantity, time, operator, resource, and variance.
- [ ] Register as Stock's production posting authority at boot.
- [ ] Accept live production commands and production or AX-history imports
  through the same execution/import contract; post material effects through
  Stock's public contract with optional opaque execution, order or batch, and
  resource references.
- [ ] Commit execution completion, Stock effects, and any required override evidence as one all-or-nothing operation.
- [ ] Preserve which definition versions governed the recorded work.

Validation: repeated submission cannot duplicate material use, and each execution's material effects appear in the same Stock ledger as warehouse movements.

#### Phase 2 — Cure hold and override

- [ ] Refuse consumption of material that has not met its configured hold, such as a cure minimum, by default.
- [ ] Allow an override only with an explicit Base Authz capability and a mandatory reason.
- [ ] Record the override's actor, time, reason, and affected unit immutably, in the same transaction as the consumption.

Validation: an under-cured unit is refused without the capability, and an authorised override leaves one immutable record beside its Stock effect.

#### Phase 3 — Production trace

- [ ] Build trace as a read model over Inventory/Stock genealogy.
- [ ] Show the production runs, operations, and resources associated with material ancestry.
- [ ] Prove backward trace from output to source and forward trace from receipt to produced outputs.

Validation: trace reads Stock's ancestry and stores no second parent/child ledger.

### Planning, Maintenance, and Costing modules

- [ ] Define Planning (MPS, MRP, capacity) only after an owner confirms a shared scheduling or material-requirements need.
- [ ] Define Maintenance (equipment, preventive maintenance) only after an owner confirms the equipment and downtime workflow.
- [ ] Define Costing (standard and actual cost, variance) only after an owner confirms valuation rules.

Validation: each later module has an explicit owner, public contract, and dependency direction before it joins a release.

### Neighbouring capability Domains

- [ ] Define the Quality Domain, including inspection, nonconformance, corrective action, and QAC, only after an owner approves its public contract.
- [ ] Define Document/Change Control, Metrology/Calibration, Controlled Records, Supplier Quality, and EHS only after an owner approves each workflow.

Validation: Manufacturing links to each neighbour only through that Domain's public contract.

The generic contracts should be checked against Mr Packaging Sdn Bhd and SBG as different factory examples; their plant rules remain in their customer requirements and Extensions.
