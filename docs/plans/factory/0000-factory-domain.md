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
codex/gpt-6-luna-xhigh (earlier work), codex/gpt-6-sol-medium (Factory boundary revision),
claude/claude-opus-5.5 (earlier review)

## Problem Essence

A factory adopter needs an obvious home for the capabilities used to run a factory. Splitting inventory and production into separate Domains makes one factory application harder to understand, select, and extend.

- Inventory, product definitions, and production execution belong to the same factory capability map.
- Separate Domain repositories would make adopters assemble that map themselves, even when the modules form one operational whole.
- Module ownership still needs clear public contracts so material records, definitions, and actual work do not become one indistinct implementation.
- Editing a definition in place can make an old run appear to have followed today's instructions.
- A planned operation does not prove what was actually done, and a separate trace ledger can disagree with material ancestry.
- Customer-specific behaviour needs a place outside the reusable Factory Domain.

## Desired Outcome

Factory is one installable Domain that makes the factory capability map clear to adopters. Inventory, Product Definition, and Production Execution are its initial modules. Planning, Maintenance, and Costing join when their shared workflows and contracts are confirmed; Quality's placement is decided when its workflow is built.

- One mounted Factory repository supplies the modules a manufacturing adopter needs.
- Each module has a distinct owner and public API: Inventory for material facts, Product Definition for what and how to make, and Production Execution for actual work.
- Shared factory variation lives in Domain configuration; Extensions add only confirmed customer-specific behaviour.
- A logistics-only application may use a separately designed inventory capability. When it shares physical stock with Factory, both workflows must use one material ledger.
- Later modules have an explicit home without entering the first build before their workflows are proven.

## Top-Level Components

Factory is one cohesive Domain. Its initial build includes Inventory to record material, Product Definition to define work, and Production Execution to record what happened. The modules have separate public APIs and one installation boundary. Factory contains reusable capabilities and knows nothing about any one customer.

### Modules

- **Inventory** (`inventory`) — owns items, locations, units, the Material Transaction ledger, material units, and Lot/Unit Genealogy. A lot identifies a batch of material; a unit identifies one physical piece. Genealogy links the lots or units consumed by a transformation to those it produces, allowing backward and forward trace. Its public posting contract is detailed in [`0010-inventory-module.md`](0010-inventory-module.md).
- **Product Definition** (`product_definition`) — defines what is made and how: links to Inventory items, versioned BOM/recipe, routings with their operations, and work-centre definitions. It also holds process configuration such as process families, tolerances, output roles, and material hold rules.
- **Production Execution** (`production_execution`) — runs production orders and their operations, and posts consumption and output through Inventory's public contract. It enforces configured holds and owns the trace read model over Inventory genealogy.
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

- **Logistics or Warehouse Domain** — may have its own inventory in a logistics-only application. If installed beside Factory over the same stock, it must use Factory Inventory's public contract or follow an explicit extraction of Inventory to its own Domain.
- **Quality** — inspection, QAC cases, supplier requests, and corrective action need a confirmed workflow before placement. Keep it in Factory if it is a close production module; make it a Domain only if it is a substantial capability on its own. Decide Supplier Quality overlap at the same time.
- **Other later capabilities** — Document/Change Control, Metrology/Calibration, Controlled Records, and EHS need their own ownership decision when their workflows are confirmed.

Configuration extends a module's behaviour as data; it is not a third code layer. Inventory owns item-level units and conversions; Product Definition owns process-specific conversion bases.

## Design Decisions

### Keep Inventory inside Factory for the first build

Inventory is required to run Factory, while a warehouse-only adopter may need material records without production. Two real placements serve those needs differently.

- **Separate Inventory Domain:** supports warehouse-only installation, but makes every factory adopter mount two repositories for one capability.
- **Factory Inventory module:** gives a factory one installation boundary, but a warehouse-only adopter cannot install this module alone.
- **Recommendation — Factory Inventory now:** build for the confirmed factory workflows. If an independent warehouse capability needs the same ledger, decide whether it can use Factory's public contract or whether Inventory must be extracted before that capability lands. Extraction changes Inventory's stable module ID and requires an explicit migration and compatibility plan.

## Public Contract

Factory Inventory, Product Definition, and Production Execution give other modules and Extensions stable material and production contracts.

- Product Definition is versioned. A production order selects the BOM/recipe and routing versions used for its execution.
- An **Operation** is a logical step in a routing. A **Work Centre/Resource** is the physical machine, line, station, or capacity used for that step.
- Execution records actual inputs, outputs, quantities, location, time, operator, resource, selected definitions, and variance.
- A production order may carry an opaque demand-source reference without making Planning part of the first build. A terminal Inventory movement may carry opaque shipment and destination references without giving Inventory a shipping workflow.
- Warehouse receipts and ordinary warehouse movements post directly to Inventory. Production commands and historical production imports enter Production Execution's public contract, which validates the operation and posts Inventory effects with opaque context references.
- Only a module in Inventory's own Domain container, as declared by composition metadata, may register as a production posting authority. Production Execution is the initial registrant. Inventory names no registrant and depends on none; an Extension cannot bypass Factory's validation.
- An application has one material ledger for a given physical stock. A future warehouse or logistics Domain sharing that stock uses Factory Inventory's public contract, or Inventory is extracted to its own Domain before the new Domain lands. A separate logistics-only application may use a different inventory capability.
- Execution completion, Inventory effects, and any required override evidence succeed or fail together.
- Consumption of material under a configured hold is refused by default. An override needs an explicit Base Authz capability and a mandatory reason, and records actor, time, reason, and affected unit as an immutable record.
- Production trace reads Inventory's Lot/Unit Genealogy. It may add production context to a trace result but does not keep parent/child material ancestry of its own.
- Common process families and their rules are Domain-owned configuration. Customer Extensions use public contracts and may add behaviour only where configuration cannot express a confirmed need.
- Extensions do not read private Domain queries or tables. Each module remains complete when any customer Extension is absent.
- Canonical names are Product Definition, Formula/BOM, Routing, Operation, Work Centre/Resource, Production Order, Batch, Execution, and Trace. Optional screen labels such as Flow, Make, Blueprint, Route, Run, and Trace do not change API or stored names.

## Phases

### Inventory module

- [ ] Deliver Factory's catalog, locations, Material Transaction ledger, and Lot/Unit Genealogy through the public contract in [`0010-inventory-module.md`](0010-inventory-module.md).

Validation: receiving, storage, and production reconcile through one material history across distinct factory workflows. The customer sequence is in the [rollout plan](../domain-extension-layer-rollout.md).

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
- [ ] Register as Inventory's initial production posting authority at boot.
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

### Later modules and Quality placement

- [ ] Decide Quality's placement when an owner confirms its case, evidence, supplier-request, and corrective-action workflow. Use a Factory module if it is closely bound to production; use a separate Domain only if it is substantial on its own. Resolve Supplier Quality ownership in that decision.
- [ ] Define Planning (MPS, MRP, capacity) only after an owner confirms a shared scheduling or material-requirements need.
- [ ] Define Maintenance (equipment, preventive maintenance) only after an owner confirms the equipment and downtime workflow.
- [ ] Define Costing (standard and actual cost, variance) only after an owner confirms valuation rules.

Validation: each later module has an explicit owner, public contract, and dependency direction before it joins a release.

### Other later capabilities

- [ ] Decide ownership for Document/Change Control, Metrology/Calibration, Controlled Records, and EHS after an owner approves each workflow.

Validation: each later capability has an explicit owner and public contract before joining a release.

Customer plans provide discovery evidence and configuration values; an Extension is needed only for a confirmed behaviour the shared contracts cannot express.
