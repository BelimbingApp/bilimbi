# docs/plans/manufacturing/manufacturing-domain.md

**Status:** Proposed
**Last Updated:** 2026-09-25
**Sources:**
- `docs/architecture/0010_composition-model.md`
- `docs/plans/domain-extension-layer-rollout.md`
- `docs/plans/manufacturing/mr-packaging-requirements.md`
- `docs/plans/manufacturing/sbg-requirements.md`
- `AGENTS.md` §4, §5, and §6
- Belimbing `app/Domains/Commerce/Inventory` (item master, 3 models)
- Material-flow scout report (2026-09-25)
- [https://github.com/BelimbingApp/bilimbi/pull/800](https://github.com/BelimbingApp/bilimbi/pull/800)
- Mr Packaging Sdn Bhd requirements and SBG extension source review

**Agents:** claude/claude-opus-5, amp/medium-sol, codex/gpt-5,
codex/gpt-5.6-luna (Luna-6, dispatched by firstmate; reviewed by the
no-mistakes pipeline)

## Problem Essence

Manufacturing should solve two real factory problems first without making
either customer's vocabulary the shared product model.

- Mr Packaging Sdn Bhd needs a reliable material account for LDPE foam: what
  arrived, what entered a run, what came out, and what became trim or waste.
- SB Group needs one view across adhesive-tape materials, coating and slitting
  production, glue batches, supply, inventory value, quality work, and AX facts.
- Separate ledgers would make stock, production, and traceability disagree.
- Customer-specific code in the common Domain would make the second customer
  pay for the first customer's assumptions.

## Desired Outcome

Inventory/Stock owns the material truth, and a generic Manufacturing /
Production Operations Domain turns that truth into configured production work.

- The first build slice is a standalone Stock ledger with receiving and weigh
  tickets, followed by production runs.
- One append-only Material Transaction ledger records balanced changes for both
  companies; station, order, and operation views are filters over that ledger.
- Lot/Unit Genealogy and units of measure remain Stock capabilities, so Stock
  works with Manufacturing absent.
- Manufacturing owns definitions, execution, configuration, and trace views;
  it adds no second genealogy store.
- `MrPackaging` and `SbGroup` contain only customer behaviour that common
  contracts and Domain-owned configuration cannot express.
- Quality, Document/Change Control, Metrology/Calibration, controlled records,
  supplier quality, and EHS remain later capabilities driven by real ISO needs.

## Top-Level Components

These components describe ownership in the generic release and the customer
work each one must support.

- **Inventory/Stock** — owns items, locations, units of measure, material units,
  the one Material Transaction ledger, and Lot/Unit Genealogy.
- **Material Transaction ledger** — records immutable, balanced entries with
  native quantity, provenance, source and destination locations, actor, tenant,
  and optional opaque references to execution, order or batch, and Work
  Centre/Resource.
- **Manufacturing / Production Operations** — owns Product Definition,
  Formula/BOM, Routing, Operation, Work Centre/Resource, Production Order or
  Batch, Operation Execution, and trace views.
- **Production module** — is the first Manufacturing module. Its internal
  boundaries are `product_definition`, `process_definition`, `execution`, and
  `trace`; they are not independently selectable until a real ownership need
  appears.
- **Domain configuration** — Manufacturing owns process families, route
  templates, tolerances, output roles, cure or process gates, and
  process-specific conversion bases. Stock owns item-level conversions and
  units of measure. Base Settings remains the generic settings mechanism.
- **`MrPackaging` Extension** — holds a confirmed Mr Packaging Sdn Bhd
  integration, vocabulary, or workflow that cannot be expressed by the public
  Domain contracts and configuration.
- **`SbGroup` Extension** — holds SB Group's AX integration, adhesive-tape
  planning and source adapters, customer-specific costing, and private quality
  or portal workflows. It does not own the generic ledger or execution model.
- **Later capabilities** — Quality, Document/Change Control,
  Metrology/Calibration, records and audit, supplier quality, and EHS attach to
  the common contracts only when their business and compliance owner is clear.

## Design Decisions

### Stock and Manufacturing boundary

The two capabilities have different reasons to change, so they should not be
one repository or one private query surface.

- **Option A — combined stock and manufacturing:** fewer boundaries at first,
  but warehouse-only use acquires production concepts and every process
  variation grows the same capability.
- **Option B — standalone Inventory/Stock plus generic Manufacturing:** Stock
  owns the ledger and genealogy; Manufacturing owns definitions and execution
  and posts through Stock's public contract.
- **Option C — Stock plus customer process Extensions:** keeps the Domain small,
  but turns normal process families into duplicated customer code.
- **Recommendation — Option B:** it is the smallest honest deep-module split,
  lets Stock work alone, and gives both real customers one reusable production
  contract.

### One ledger and opaque context

All material changes need one source of truth, while Manufacturing still needs
to explain which run or resource caused each change.

- **Option A — ledger per station, order, or operation:** local screens are
  simple, but balances and ancestry drift between stores.
- **Option B — one global Material Transaction ledger with filtered views:**
  balanced transactions remain global, and views group them by execution,
  order or batch, Work Centre/Resource, location, supplier, or period.
- **Option C — one ledger plus a second Manufacturing genealogy:** trace reads
  are convenient, but two ancestry stores eventually disagree.
- **Recommendation — Option B:** Stock owns the ledger and genealogy;
  Manufacturing supplies optional opaque context references through the public
  posting contract, without making Stock understand manufacturing terms.

### Definitions, execution, and configuration

Plans describe what may happen; executions record what did happen.

- **Definitions:** Product Definition, Formula/BOM, and Routing describe the
  product and route selected for a run.
- **Execution:** Operation Execution records actual inputs, outputs, quantities,
  locations, resources, timings, variances, and the selected definition.
- **Operation versus Work Centre/Resource:** Operation is the logical step;
  Work Centre/Resource is the physical machine, line, station, or capacity.
- **Domain configuration:** process families, routes, tolerances, output roles,
  and process-specific conversion bases are data owned by Manufacturing.
- **Stock data:** items, locations, lot rules, units of measure, and item-level
  conversions remain Stock data.
- **Recommendation:** keep configuration inside the owning Domain. A third
  configuration code layer would add entropy without a demonstrated need.

### Two code layers and naming

There are only two code layers: the common Domain and customer Extensions.

- The Domain contains common logic and the configuration it owns.
- Extensions consume public contracts and add proven customer behaviour; they
  never reach into private Product Definition, Routing, Execution, ledger, or
  genealogy internals.
- Canonical names are Inventory/Stock, Manufacturing/Production, Product
  Definition, Formula/BOM, Routing, Operation, Work Centre/Resource, Production
  Order, Batch, Operation Execution, Material Transaction, Lot/Unit Genealogy,
  Quality, Planning, and Costing.
- Optional UI labels are Flow, Make, Blueprint, Route, Run, and Trace. They do
  not change persisted or API names.
- `Material Ledger` is reserved for future valuation; the operational record is
  the Material Transaction ledger.

### Later ISO-driven capabilities

The ledger supports evidence, but it is not certification by itself.

- Quality covers product and process results, nonconformance, and corrective
  action when that capability has an owner.
- Document/Change Control covers controlled procedures and revisions.
- Metrology/Calibration covers measurement equipment and calibration evidence.
- Records and audit, supplier quality, and EHS are separate later capabilities.
- ISO 9001, ISO 14001, and ISO 45001 guide the later work; IATF 16949 is added
  only when an automotive customer requires it.

## Public Contract

The public surface must let both customers operate without learning private
schemas or query details.

- Stock is installable without Manufacturing and exposes item, unit, location,
  material-unit, stock-position, transaction, and genealogy operations.
- A Material Transaction is immutable, balanced, attributable, and append-only.
  Corrections are compensating transactions with a reason and a reference to
  what they correct.
- Each entry preserves native quantity and unit, provenance (`measured`,
  `declared`, `counted`, or `derived`), a versioned conversion basis when used,
  and a normalised mass equivalent when reconciliation needs one.
- The posting contract accepts optional opaque execution, order or batch, and
  Work Centre/Resource references. Stock stores them without interpreting
  Manufacturing semantics.
- Idempotent submission prevents a retry from double-posting. Concurrent
  consumption prevents the same quantity being consumed twice. Backdating
  preserves effective and recorded times. Reversal uses a compensating
  transaction.
- A transform records input, output, parent/child identity, and variance. It
  may record configured variance rather than hiding material reality.
- Lot/Unit Genealogy is queryable backward from output to receipts and forward
  from receipts to descendants. Manufacturing trace reads this public contract
  and stores no second genealogy.
- Manufacturing separates definitions from execution and posts execution
  effects through Stock's public contract.
- Under-cured consumption is refused by default. An override requires an
  explicit Base Authz capability and a mandatory reason and is kept as an
  immutable operational record. This record is not a Quality-module claim.
- `MrPackaging` and `SbGroup` are complete only at their public seams. They may
  add customer behaviour, but cannot duplicate the common ledger, genealogy,
  units of measure, or execution semantics.

## Phases

### Phase 1 — Stock ledger, receiving, and weigh tickets

This first slice gives both companies a trustworthy material account before
production-specific screens are built.

- **Mr Packaging Sdn Bhd receives:** supplier, vehicle, gross, tare, net,
  declared weight, measured weight, material, location, actor, and variance in
  one receiving flow for the Muar LDPE foam operation.
- **SB Group receives:** a common stock position and source-aware material
  movement foundation for BA, BOPP, glue, coating, and other mapped materials;
  no SBG-specific planning logic is put into Stock.
- [ ] Port Belimbing's canonical item master (`app/Domains/Commerce/Inventory`)
  into Stock, preserving its schema under `AGENTS.md` §5.
- [ ] Add Stock locations, units of measure, material units, and tenant-scoped
  public operations around that item master.
- [ ] Record receiving as one balanced transaction and retain declared versus
  measured evidence.
- [ ] Add idempotency, concurrent-consumption protection, backdating, reversal,
  and append-only correction behaviour.
- [ ] Prove stock position and Lot/Unit Genealogy reads without Manufacturing
  mounted.

Validation: a seeded Muar receipt and an SBG BA/BOPP receipt reconcile to known
weights and quantities, and no second ledger is needed.

### Phase 2 — Production runs and genealogy

This phase turns the ledger into a production record while keeping the same
Stock boundary.

- **Mr Packaging Sdn Bhd receives:** individually identified foam rolls,
  extrusion inputs and outputs, 7–10 day cure age, and trace from roll to
  finished pack.
- **SB Group receives:** glue batches with reactor, operator, wet/dry output,
  material lots, and quality result references, plus coating and slitting runs
  linked to AX production-order facts.
- [ ] Add Product Definition, Formula/BOM, Routing, Operation, Work
  Centre/Resource, Production Order or Batch, and Operation Execution.
- [ ] Post each execution's inputs and outputs through Stock with opaque
  execution, order or batch, and resource references.
- [ ] Implement Manufacturing trace as views over Stock genealogy.
- [ ] Add a configurable consumption hold that refuses under-cured input by
  default, and an override that requires an explicit Base Authz capability and
  a mandatory reason and is kept as an immutable operational record.
- [ ] Configure Mr Packaging cure gates and foam process data without changing
  common execution code.
- [ ] Configure SBG glue, coating, and slitting process families without
  making SBG's AX or recipe vocabulary canonical.

Validation: one configured Muar run and one configured SBG run can be traced in
both directions through the same Stock contract.

### Phase 3 — Reconciliation and customer read models

This phase makes operational differences visible without inventing parallel
balances.

- **Mr Packaging Sdn Bhd receives:** per-supplier, per-run, per-operation,
  per-location, and monthly input/output/trim/waste reconciliation with
  measured-versus-derived provenance.
- **SB Group receives:** raw-material yield by production order and coating
  line, BA/BOPP stock and safety-stock alerts, procurement commitments, source
  freshness, inventory-value revisions, glue dashboard summaries, and drilldown
  to validated facts.
- [ ] Build filtered ledger views and reconciliation read models from Stock and
  Manufacturing public APIs.
- [ ] Keep raw AX source facts and source timestamps in `SbGroup`'s Extension
  through `AxConnector`; do not move AX transport into the generic Domain.
- [ ] Keep customer dashboards, planning formulas, and private quality work in
  `SbGroup`; expose only approved actuals or summaries to common contracts.
- [ ] Reconcile known Muar receipts and SBG AX/workbook periods before calling
  either customer workflow accepted.

Validation: each report names its source, owner, freshness, unit, and formula;
no report creates a second balance or genealogy.

### Phase 4 — Customer Extensions and integrations

This phase adds only behaviour that common configuration and contracts cannot
express.

- **Mr Packaging Sdn Bhd receives:** `MrPackaging` only for a confirmed
  customer vocabulary, integration, calculation, alert, approval, or report.
- **SB Group receives:** `SbGroup` ownership of AX integration, BA/BOPP IBP,
  procurement and supplier commitments, inventory-value reports, glue
  production source readiness, QAC workflows, and private dashboards.
- [ ] Keep process families, route steps, tolerances, output roles, cure
  duration, and unit conversions in Domain configuration first.
- [ ] Mount either Extension only when a public-contract seam is documented.
- [ ] Prove the common Domain remains complete when `MrPackaging` or `SbGroup`
  is absent and removing an Extension does not delete durable data.
- [ ] Keep AX writes out of the generic Domain; any future SBG write uses an
  approved AX AIF or staging contract, never raw SQL to AX application tables.

Validation: both Extensions can be removed from a generic release without
changing the common ledger or execution behaviour.

### Phase 5 — Later capability modules

This phase adds standards-driven capability only after a business owner and
evidence requirement exist.

- **Mr Packaging Sdn Bhd receives:** measurement, document, supplier-quality,
  and EHS controls only when its certification scope requires them.
- **SB Group receives:** QAC, controlled records, calibration, supplier
  quality, and EHS contracts that connect to its production and AX evidence.
- [ ] Assign ISO 9001, ISO 14001, ISO 45001, or customer requirements to
  explicit capability owners.
- [ ] Define public contracts without adding hidden fields to Stock's ledger.
- [ ] Add IATF 16949 only when an automotive customer requires it.
- [ ] Prove each later capability can be absent without changing the core
  ledger contract or making a certification claim.

Validation: every later module has an owner, public contract, evidence plan,
and composition boundary before implementation begins.
