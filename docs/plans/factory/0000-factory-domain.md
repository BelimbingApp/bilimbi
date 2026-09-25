# docs/plans/factory/0000-factory-domain.md

**Status:** Proposed
**Last Updated:** 2026-09-25
**Sources:**
- [`docs/plans/factory/0010-inventory-module.md`](0010-inventory-module.md)
- [`docs/plans/factory/mr-packaging-requirements.md`](mr-packaging-requirements.md)
- [`docs/plans/factory/sbg-requirements.md`](sbg-requirements.md)
- [`docs/plans/domain-extension-layer-rollout.md`](../domain-extension-layer-rollout.md)
- [`docs/architecture/0010_composition-model.md`](../../architecture/0010_composition-model.md)
- [`AGENTS.md`](../../../AGENTS.md) §§4–6
- [Pull request 800](https://github.com/BelimbingApp/bilimbi/pull/800)
- [Pull request 804](https://github.com/BelimbingApp/bilimbi/pull/804)

**Agents:** codex/gpt-5.6-luna (earlier work),
codex/gpt-6-luna-xhigh (earlier work), codex/gpt-6 (Factory boundary revision),
claude/claude-opus-5.5 (no-mistakes review agent), codex/gpt-6-sol-medium

## Problem Essence

A factory adopter needs an obvious home for the capabilities used to run a factory. Splitting inventory and production into separate Domains makes one factory application harder to understand, select, and extend.

- Inventory, product definitions, production execution, and later quality work belong to the same factory capability map.
- Separate Domain repositories would make adopters assemble that map themselves, even when the modules form one operational whole.
- Module ownership still needs clear public contracts so material records, definitions, and actual work do not become one indistinct implementation.
- Customer-specific behaviour needs a place outside the reusable Factory Domain.

## Desired Outcome

Factory is one installable Domain that makes the factory capability map clear to adopters. Inventory, Product Definition, and Production Execution are its initial modules; Quality, Planning, Maintenance, and Costing join when their shared workflows and contracts are confirmed.

- One mounted Factory repository supplies the modules a manufacturing adopter needs.
- Each module has a distinct owner and public API: Inventory for material facts, Product Definition for what and how to make, and Production Execution for actual work.
- Shared factory variation lives in Domain configuration; Extensions add only confirmed customer-specific behaviour.
- A logistics or warehouse adopter may use a separately designed inventory capability rather than install Factory.
- Later modules have an explicit home without entering the first build before their workflows are proven.

## Top-Level Components

Factory is one cohesive Domain. Its initial build includes Inventory to record material, Product Definition to define work, and Production Execution to record what happened. The modules have separate public APIs and one installation boundary. Factory contains reusable capabilities and knows nothing about any one customer.

### Modules

- **Inventory** (`inventory`) — owns items, locations, units, the Material Transaction ledger, material units, and Lot/Unit Genealogy. A lot identifies a batch of material; a unit identifies one physical piece. Genealogy links the lots or units consumed by a transformation to those it produces, allowing backward and forward trace. Its public posting contract is detailed in [`0010-inventory-module.md`](0010-inventory-module.md).
- **Product Definition** (`product_definition`) — defines what is made and how: links to Inventory items, versioned BOM/recipe, routings with their operations, and work-centre definitions. It also holds process configuration such as process families, tolerances, output roles, and material hold rules.
- **Production Execution** (`production_execution`) — runs production orders and their operations, and posts consumption and output through Inventory's public contract. It enforces configured holds and owns the trace read model over Inventory genealogy.
- **Quality** (`quality`) — **later.** Inspection, nonconformance, and corrective action when an owner confirms the shared workflow and contract.
- **Planning** (`planning`) — **later.** Master production schedule, material requirements planning (MRP), and capacity. It waits until a customer needs a shared schedule or MRP; customer-specific planning stays in that customer's Extension until then.
- **Maintenance** (`maintenance`) — **later.** Equipment records and preventive maintenance for work centres. It waits until an owner confirms the equipment and downtime workflow.
- **Costing** (`costing`) — **later.** Standard and actual production cost and their variance, read from Inventory transactions and execution records. It waits until an owner confirms valuation rules; Inventory reserves "Material Ledger" for that valuation.

### Repository structure

Factory mounts as one Domain repository under the Domain root. Its initial modules have separate public APIs and participate in the same installed capability.

```text
apps/domains/factory/            # Factory's nested Git repository
├── inventory/
├── product_definition/
└── production_execution/
```

### Neighbouring capabilities

- **Logistics or Warehouse Domain** — may own inventory for a different business workflow. Its design is separate from Factory Inventory; any shared contract needs a proven cross-domain use.
- **Other later capabilities** — Document/Change Control, Metrology/Calibration, Controlled Records, Supplier Quality, and EHS need their own ownership decision when their workflows are confirmed.

Configuration extends a module's behaviour as data; it is not a third code layer. Inventory owns item-level units and conversions; Product Definition owns process-specific conversion bases.

## Public Contract

Factory Inventory, Product Definition, and Production Execution give other modules and Extensions stable material and production contracts.

- Product Definition is versioned. A production order selects the BOM/recipe and routing versions used for its execution.
- An **Operation** is a logical step in a routing. A **Work Centre/Resource** is the physical machine, line, station, or capacity used for that step.
- Execution records actual inputs, outputs, quantities, location, time, operator, resource, selected definitions, and variance.
- Warehouse receipts and ordinary warehouse movements post directly to Inventory. Production commands and historical production imports enter Production Execution's public contract, which validates the operation and posts Inventory effects with opaque context references.
- Production Execution registers itself at boot as Inventory's production posting authority. Inventory refuses production or transform postings from anyone else, so an Extension cannot bypass Factory's validation.
- Execution completion, Inventory effects, and any required override evidence succeed or fail together.
- Consumption of material under a configured hold is refused by default. An override needs an explicit Base Authz capability and a mandatory reason, and records actor, time, reason, and affected unit as an immutable record.
- Production trace reads Inventory's Lot/Unit Genealogy. It may add production context to a trace result but does not keep parent/child material ancestry of its own.
- Common process families and their rules are Domain-owned configuration. Customer Extensions use public contracts and may add behaviour only where configuration cannot express a confirmed need.
- Extensions do not read private Domain queries or tables. Each module remains complete when any customer Extension is absent.
- Canonical names are Product Definition, Formula/BOM, Routing, Operation, Work Centre/Resource, Production Order, Batch, Execution, and Trace. Optional screen labels such as Flow, Make, Blueprint, Route, Run, and Trace do not change API or stored names.

## Phases

### Build order

- [ ] **First build — Mr Packaging:** deliver Inventory, Product Definition, and Production Execution together; validate the generic contracts from receipt and roll identity through production, conversion, and despatch against [Mr Packaging's requirements](mr-packaging-requirements.md).
- [ ] **Second build — SBG:** validate the same Factory modules against glue, coating, and slitting work, including production history submitted through the public import contract. Keep AX mapping and SBG workflows in [the SBG plan](sbg-requirements.md).

### Inventory module

- [ ] Deliver Factory's catalog, locations, Material Transaction ledger, and Lot/Unit Genealogy through the public contract in [`0010-inventory-module.md`](0010-inventory-module.md).

Validation: the first build reconciles Mr Packaging's receiving, storage, and production through one material history; the second build proves the same contract with SBG.

### Product Definition module

#### Phase 1 — Products, BOMs, and routings

- [ ] Link product definitions to Inventory items and define versioned Formula/BOM contracts.
- [ ] Define versioned routings, logical operations, inputs, outputs, and allowed work centres/resources.
- [ ] Keep process families, tolerances, output roles, and material hold rules as configuration data.

Validation: an order can select a specific product and routing revision without relying on a customer Extension.

### Production Execution module

#### Phase 1 — Orders, execution, and Inventory posting

- [ ] Record a production order or batch and its actual operation executions.
- [ ] Capture actual input, output, quantity, time, operator, resource, and variance.
- [ ] Register as Inventory's production posting authority at boot.
- [ ] Accept live production commands and historical production imports through the same execution/import contract; post material effects through Inventory's public contract with optional opaque execution, order or batch, and resource references.
- [ ] Commit execution completion, Inventory effects, and any required override evidence as one all-or-nothing operation.
- [ ] Preserve which definition versions governed the recorded work.

Validation: repeated submission cannot duplicate material use, and each execution's material effects appear in the same Inventory ledger as warehouse movements.

#### Phase 2 — Material holds and overrides

- [ ] Refuse consumption of material that has not met its configured hold by default.
- [ ] Allow an override only with an explicit Base Authz capability and a mandatory reason.
- [ ] Record the override's actor, time, reason, and affected unit immutably, in the same transaction as the consumption.

Validation: a held unit is refused without the capability, and an authorised override leaves one immutable record beside its Inventory effect.

#### Phase 3 — Production trace

- [ ] Build trace as a read model over Inventory genealogy.
- [ ] Show the production runs, operations, and resources associated with material ancestry.
- [ ] Prove backward trace from output to source and forward trace from receipt to produced outputs.

Validation: trace reads Inventory's ancestry and stores no second parent/child ledger.

### Quality, Planning, Maintenance, and Costing modules

- [ ] Define Quality (inspection, nonconformance, and corrective action) only after an owner confirms its shared workflow and public contract.
- [ ] Define Planning (MPS, MRP, capacity) only after an owner confirms a shared scheduling or material-requirements need.
- [ ] Define Maintenance (equipment, preventive maintenance) only after an owner confirms the equipment and downtime workflow.
- [ ] Define Costing (standard and actual cost, variance) only after an owner confirms valuation rules.

Validation: each later module has an explicit owner, public contract, and dependency direction before it joins a release.

### Other later capabilities

- [ ] Decide ownership for Document/Change Control, Metrology/Calibration, Controlled Records, Supplier Quality, and EHS after an owner approves each workflow.

Validation: each later capability has an explicit owner and public contract before joining a release.

The first build proves the generic contracts against Mr Packaging Sdn Bhd; the second checks them against SBG. Their customer plans provide discovery evidence and configuration values; an Extension is needed only for a confirmed behaviour the shared contracts cannot express.
