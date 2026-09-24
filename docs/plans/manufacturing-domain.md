# docs/plans/manufacturing-domain.md

**Status:** Proposed
**Last Updated:** 2026-09-25
**Sources:**
- `docs/architecture/0010_composition-model.md`
- `docs/plans/domain-extension-layer-rollout.md`
- `docs/plans/commerce-material-flow-ledger.md`
- `AGENTS.md` §4, §6
- Material-flow scout report (2026-09-25), with the accepted decision to use a
  generic Manufacturing / Production Operations Domain
- https://github.com/BelimbingApp/bilimbi/pull/800

**Agents:** claude/claude-opus-5, amp/medium-sol, codex/gpt-5

## Problem Essence

Building manufacturing around one customer's LDPE foam process would make
that process the product model. Bilimbi has no agreed boundary between stock,
production, configuration, and customer behaviour, so that outcome is the
default.

- Stock, genealogy, process definitions, execution, configuration, and
  customer-specific behaviour have no declared owners.
- Without one owner, each operation, order, or station tends to grow its own
  ledger, and parallel ledgers cannot reconcile.
- Customer rules written into shared code block the second target, SBG, from
  reusing the same capability.

## Desired Outcome

Stock owns the material truth, a generic Domain owns production, and
customer Extensions hold only what configuration cannot express. Each concern
then has one owner, and a second customer reuses the same code.

- Inventory/Stock works standalone with one append-only Material Transaction
  ledger, Lot/Unit Genealogy, and units of measure.
- A generic Manufacturing / Production Operations Domain defines and executes
  configured processes through Stock's public contracts.
- Customer Extensions contain only behaviour that the common contracts and
  configuration cannot express.
- Mr Packaging Sdn Bhd's LDPE foam workflow and SBG's adhesive-tape workflow
  validate the model without becoming its hidden assumptions.

## Top-Level Components

- **Inventory/Stock** — owns material items, units of measure, locations, the
  one append-only Material Transaction ledger, and Lot/Unit Genealogy. It
  remains useful when Manufacturing is not mounted.
- **Material Transaction ledger** — records balanced, immutable stock changes
  with native observations, provenance, source and destination locations, and
  optional opaque context references. Per-operation, per-order, and
  per-station ledgers are filtered views, never another source of truth.
- **Manufacturing / Production Operations Domain** — owns product and process
  definitions, routes, operations, work-centre/resource assignment, orders or
  batches, executions, and manufacturing-side trace views. Production is the
  first module; `product_definition`, `process_definition`, `execution`, and
  `trace` are internal boundaries until real module selection is required.
- **Configuration ownership** — Manufacturing owns process families, route
  templates, operation and output-role configuration, tolerances, and
  process-specific conversion bases. Stock owns items, locations, lot rules,
  units of measure, and item-level conversions. Base Settings remains the
  generic settings mechanism.
- **Extensions** — customer-specific behaviour that consumes public Domain
  contracts, such as an integration, vocabulary mapping, or a calculation
  that cannot be represented by common logic and configuration. Mr Packaging
  Sdn Bhd's Extension is `MrPackaging`; SBG already has its own Extension.
- **Later capability modules** — Quality, Document/Change Control,
  Metrology/Calibration, controlled records and audit, supplier quality, and
  EHS are separate ISO-driven capabilities around the operational ledger.
  They are not hidden fields or claims made by this plan.

## Design Decisions

### Boundary between Stock and Manufacturing

**Option A — one combined manufacturing-and-stock Domain.** This minimizes
initial repository boundaries, but makes warehouse-only deployments acquire
manufacturing concepts and forces every future process variation through one
large capability.

**Option B — Stock plus a generic Manufacturing / Production Operations
Domain.** Stock owns the ledger and genealogy; Manufacturing owns definitions
and execution and posts transactions through Stock's public contract. This
keeps each business capability coherent and lets Stock work alone.

**Option C — Stock plus customer-specific process Extensions.** This keeps the
common layer small, but makes standalone manufacturing concepts customer code,
duplicates process logic, and turns the first customer's vocabulary into a
de facto framework.

**Recommended: B.** It gives the smallest stable public boundaries with real
business meaning. It follows root `AGENTS.md`'s deep-module and dependency
rules, avoids sibling-private access, and earns generality from two real
process families rather than from speculative abstractions.

### One ledger and context references

**Option A — one ledger per station, operation, or order.** Local screens and
schemas can mirror the language of each workflow, but balances drift and
cross-step ancestry becomes a reconciliation exercise between stores.

**Option B — one global Material Transaction ledger with filtered views.** A
transaction is the immutable unit of record and contains balanced entries;
views group it by operation execution, order or batch, Work Centre/Resource,
location, or date.

**Option C — one ledger plus duplicated manufacturing genealogy.** This makes
manufacturing trace reads convenient, but creates two sources of ancestry and
eventual disagreement about what was consumed or produced.

**Recommended: B.** Stock owns the one append-only ledger and Lot/Unit
Genealogy. Manufacturing may attach optional opaque references for operation
execution, order or batch, and Work Centre/Resource through Stock's public
posting contract. Stock does not interpret those references or depend upward;
Manufacturing trace is a read model over Stock genealogy and stores no second
genealogy.

### Common Domain versus Extensions

**Option A — hardcode each plant's process in Manufacturing.** The first
workflow is fast to demonstrate, but every new plant adds branches to common
logic and makes the Domain dishonest about what is generic.

**Option B — make every variation an Extension.** This protects the common
Domain, but moves ordinary process-family configuration into customer code and
duplicates the same execution semantics across customers.

**Option C — common logic and Domain-owned configuration, with Extensions only
for proven customer behaviour.** Process families, route templates,
tolerances, output roles, and conversion bases are data; an Extension such as
`MrPackaging` or SBG's Extension is added only when it consumes a public
contract for a real adaptation.

**Recommended: C.** It keeps two code layers only — Domain and Extensions —
while making configuration explicit and inspectable. It reduces entropy,
preserves honest ownership, and prevents a third configuration-code layer from
forming.

### Naming and later ISO capabilities

The canonical names are Inventory/Stock, Manufacturing/Production, Product
Definition, Formula/BOM, Routing, Operation, Work Centre/Resource, Production
Order, Batch, Operation Execution, Material Transaction, Lot/Unit Genealogy,
Quality, Planning, and Costing. Optional UI labels are Flow, Make, Blueprint,
Route, Run, and Trace. `Material Ledger` is reserved for a future valuation
capability; the operational record is the Material Transaction ledger.

Quality, Document/Change Control, Metrology/Calibration, controlled records,
supplier quality, and EHS are later modules driven by the applicable ISO
requirements. IATF 16949 is added only when an automotive customer requires
it. The operational ledger and trace views do not by themselves constitute
certification evidence.

## Public Contract

- Stock is installable and useful without Manufacturing. It exposes public
  operations for items, units of measure, locations, material units,
  transactions, stock positions, and genealogy without exposing private
  schemas or queries.
- A Material Transaction is immutable, balanced, attributable, and append-only.
  Corrections are compensating transactions with a reason and reference to
  what they correct; nothing is edited or deleted in place.
- Every entry preserves its native observed quantity and unit, provenance
  (`measured`, `declared`, `counted`, or `derived`), any versioned conversion
  basis, and a normalised mass equivalent when reconciliation needs one.
  Derived mass is never presented as an observed fact.
- The posting contract supports optional opaque references to an operation
  execution, order or batch, and Work Centre/Resource. These references are
  context, not Stock-owned manufacturing semantics.
- The ledger contract defines idempotent submission, concurrent-consumption
  protection, effective versus recorded time for backdating, and compensating
  reversal. A transform may record variance within configured tolerance rather
  than hiding or rejecting material reality.
- Lot/Unit Genealogy is owned by Stock and is queryable in both directions.
  Manufacturing trace reads that contract and may expose which run, operation,
  and resource produced or consumed a unit without duplicating ancestry.
- Manufacturing separates definitions from execution. Product Definition,
  Formula/BOM, and Routing describe what may be made; Operation Execution
  records actual inputs, outputs, quantities, resources, locations, timings,
  and variance while retaining the selected definition and route context.
- Operation is the logical step. Work Centre/Resource is the physical machine,
  line, station, or other capacity performing it. Both may be referenced by
  execution context without making Stock understand either concept.
- Manufacturing owns its process configuration as data. Customer Extensions
  cannot reach into Product Definition, Routing, Execution, or ledger internals;
  they consume documented public contracts. `MrPackaging` is the named
  customer Extension for Mr Packaging Sdn Bhd, and SBG's existing Extension
  remains separate.
- Optional UI labels never change canonical persisted or API names. The Domain
  and Extensions do not claim that the ledger alone satisfies ISO or other
  certification requirements.

## Phases

### Phase 1 — Composition and boundary proof

Goal: prove the generic capability can be mounted and removed through the
composition model without hard-coded customer names.

- [ ] Complete the disposable Domain and Extension proof in
  `docs/plans/domain-extension-layer-rollout.md`.
- [ ] Prove Inventory/Stock can compile, migrate, and serve its public stock
  and genealogy contracts with Manufacturing absent.
- [ ] Prove Manufacturing/Production declares a dependency on Stock's public
  contract and never depends on Stock's private tables or queries.
- [ ] Prove `MrPackaging` and SBG Extensions can be absent without removing
  common Domain behaviour or durable data.

Validation: one disposable release demonstrates dependency, migration,
contribution, route, removal, and release-boot behaviour for mounted Domains
and Extensions.

### Phase 2 — Inventory/Stock foundation

Goal: establish one trustworthy operational ledger independently of any plant
process.

- [ ] Implement item, unit-of-measure, location, material-unit, and lot
  identity contracts.
- [ ] Implement balanced append-only Material Transactions with native
  observations, provenance, conversion basis, and normalised mass where
  applicable.
- [ ] Implement idempotency, concurrent consumption, backdating, reversal,
  variance capture, and bidirectional Lot/Unit Genealogy.
- [ ] Provide stock position and genealogy read models without per-station or
  per-order ledgers.

Validation: seeded receipts and transforms reconcile; tenant boundaries,
append-only enforcement, ancestry traversal, and double-consumption tests pass.

### Phase 3 — Production module

Goal: add generic definitions and execution while preserving Stock's
standalone boundary.

- [ ] Add Product Definition, Formula/BOM, Routing, Operation,
  Work Centre/Resource, Production Order or Batch, and Operation Execution
  contracts.
- [ ] Keep `product_definition`, `process_definition`, `execution`, and
  `trace` as internal boundaries; split modules only after a real selection or
  ownership need is demonstrated.
- [ ] Post execution inputs and outputs through Stock's public contract with
  optional opaque execution, order or batch, and Work Centre/Resource context.
- [ ] Implement Manufacturing trace as views over Stock genealogy, not a
  second ancestry store.
- [ ] Store process families, route templates, tolerances, output roles, and
  process-specific conversion bases as Domain-owned configuration data.

Validation: a configured execution can be posted and traced in both directions
through Stock, while Stock remains usable with Production absent.

### Phase 4 — Validating process families and Extensions

Goal: demonstrate that two real process families fit the common contracts
without customer logic leaking into them.

- [ ] Configure Mr Packaging Sdn Bhd's LDPE foam flow and SBG's adhesive-tape
  flow using the common Production module.
- [ ] Record plant-specific acceptance and reconciliation requirements in
  `docs/plans/commerce-material-flow-ledger.md`, rather than adding them here.
- [ ] Create `MrPackaging` only for a confirmed customer-specific behaviour
  that consumes a public contract; keep process steps, routes, tolerances, and
  unit conversions in Domain configuration.
- [ ] Keep SBG's existing Extension independent and prove both Extensions can
  be omitted from the common Domain release.

Validation: the two configurations exercise definitions, execution, trace,
ledger context, and reconciliation without hard-coded customer branches.

### Phase 5 — Later operational capability modules

Goal: add standards-driven capabilities only when a real requirement and
ownership boundary exist.

- [ ] Identify the applicable ISO 9001, ISO 14001, ISO 45001, or customer
  requirements and assign each to an explicit capability module.
- [ ] Define public contracts for Quality, Document/Change Control,
  Metrology/Calibration, controlled records and audit, supplier quality, and
  EHS without adding hidden fields to Stock's ledger.
- [ ] Add IATF 16949 capability only when an automotive customer requires it.
- [ ] Prove each later module can be absent without changing the core ledger
  contract or falsifying certification claims.

Validation: each capability has an owner, public contract, evidence plan, and
composition boundary before implementation begins.
