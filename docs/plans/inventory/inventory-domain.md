# docs/plans/inventory/inventory-domain.md

**Status:** Proposed
**Last Updated:** 2026-09-25
**Sources:**
- [`docs/plans/manufacturing/manufacturing-domain.md`](../manufacturing/manufacturing-domain.md)
- [`docs/plans/commerce-material-flow-ledger.md`](../commerce-material-flow-ledger.md)
- [`docs/plans/domain-extension-layer-rollout.md`](../domain-extension-layer-rollout.md)
- [`docs/architecture/0010_composition-model.md`](../../architecture/0010_composition-model.md)
- [`AGENTS.md`](../../../AGENTS.md) §§4–6
- Belimbing `app/Domains/Commerce/Inventory` item master and models
- [Pull request 800](https://github.com/BelimbingApp/bilimbi/pull/800)
- [Pull request 804](https://github.com/BelimbingApp/bilimbi/pull/804)

**Agents:** codex/gpt-5.6-luna (earlier work), codex/gpt-6-luna-xhigh (this revision),
claude/claude-opus-5.5 (no-mistakes review agent)

## Problem Essence

Material records cannot be trusted when receipts, use, transformations, and adjustments live in separate balances. Inventory/Stock must give every workflow one account of material and its history, even when Manufacturing is not installed.

- Separate ledgers for receiving, production, and work areas can disagree about the same material.
- A balance alone cannot explain which receipt or earlier lot produced an output.
- Changing a quantity in place hides what happened and who corrected it.
- A stock service tied to production cannot support warehouse work on its own.

## Desired Outcome

Inventory/Stock owns items, locations, units of measure, material transactions, and Lot/Unit Genealogy as one standalone Domain. Other Domains post material changes through its public contract and read the same history.

- One append-only Material Transaction ledger records every movement, receipt, use, output, and correction.
- Current stock positions are views over that ledger, not a second source of truth.
- Lot/Unit Genealogy follows material from receipt through transformations to later outputs.
- Each transaction keeps its original quantity and unit, evidence source, and any conversion basis used for reporting.
- Callers may attach optional opaque context references without making Stock depend on their business meaning.
- The same contract supports warehouse-only use and production that is supplied by Manufacturing.
- Production and transform postings come only from a registered posting authority, so no caller can skip the production rules that authority enforces.

## Top-Level Components

Inventory/Stock is one Domain. Its first module owns these related responsibilities:

- **Item and material records** — identify stockable materials and products while preserving the existing item master contract.
- **Locations and stock position** — record where material is held and present the current position by item, location, lot, and unit.
- **Units of measure and conversions** — preserve each item's native unit and the versioned basis for a converted quantity.
- **Material Transaction ledger** — keep balanced, append-only records for receipts, transfers, consumption, outputs, and new correction transactions that refer to what they correct.
  “Material Ledger” is reserved for future valuation; the operational record is the Material Transaction ledger.
- **Material units and Lot/Unit Genealogy** — identify lots or individual units and link inputs to outputs when a material transformation occurs.
- **Posting and query contract** — let other modules record and read stock facts without using Stock's tables or private queries.
- **Posting-authority registry** — records which Domain module may post production or transform context. Stock names no such module and depends on none.

The Manufacturing Domain is separate and has its own plan. It supplies optional execution, order or batch, and Work Centre/Resource references when it posts. Stock stores those references as opaque context; it does not resolve or interpret them. Its Production Execution module registers as Stock's posting authority. See [`manufacturing-domain.md`](../manufacturing/manufacturing-domain.md) for its modules and ownership.

## Design Decisions

### Keep Stock separate from production

Stock must remain useful to a warehouse when no production workflow is mounted.

- **Option A — combine Stock and Manufacturing:** fewer packages at first, but warehouse use depends on production concepts and production-specific changes share Stock's release boundary.
- **Option B — create a ledger for each customer:** each customer can move quickly, but balances and history split as soon as stock crosses workflows.
- **Option C — standalone Inventory/Stock with public posting contracts:** Stock owns material facts, while Manufacturing and other callers provide context through a small public seam.
- **Recommendation — Option C:** it keeps one durable material owner and allows Stock to run without Manufacturing.

### Use one ledger for all material changes

A single material account makes balances and source evidence comparable across locations and workflows.

- **Option A — separate ledgers by operation or work area:** each screen is simple, but reconciliation must join competing balances.
- **Option B — store balances as the source of truth:** reads are fast, but the system cannot reconstruct why a balance changed.
- **Option C — one append-only Material Transaction ledger with position views:** every change has one record, and screens filter or summarize that record.
- **Recommendation — Option C:** it preserves the event history and gives each view the same source of truth.

### Keep material ancestry in Stock

Every Domain that handles material needs the same lineage, whether or not it calls its steps production.

- **Option A — let each caller keep its own genealogy:** callers can use local terms, but ancestry diverges across workflows.
- **Option B — store genealogy in Manufacturing:** production trace is convenient, but Stock requires Manufacturing before any ancestry can be read.
- **Option C — let Stock own Lot/Unit Genealogy and expose queries:** callers attach their context while Stock maintains material parent and child links.
- **Recommendation — Option C:** Stock can operate alone, and no caller needs a second genealogy store.

### Accept production postings only from a registered authority

Production rules such as a cure hold live in Manufacturing, but Stock records the material effect. Stock must refuse a production posting that skipped those rules without depending on Manufacturing.

- **Option A — trust callers and rely on review:** no new seam, but an Extension can post production usage straight to Stock and nothing refuses it.
- **Option B — gate production postings behind a Base Authz capability:** reuses authorization, but capabilities belong to people, so any caller acting for a privileged user still bypasses Manufacturing.
- **Option C — a Stock-owned posting-authority registry:** Stock refuses production or transform context unless the posting comes from a registered authority. Only a Domain-layer module, as declared in the composition metadata, may register; Manufacturing registers itself at boot.
- **Recommendation — Option C:** the refusal happens in Stock, the dependency still points from Manufacturing to Stock, and warehouse-only use needs no authority.

## Public Contract

The public contract makes each quantity and its history explainable.

- A Material Transaction is append-only, attributable, and balanced across its source and destination effects. A correction adds a new transaction with a reason and a reference to the original; it never edits or deletes the old record.
- Every entry retains its native quantity and unit, whether it was measured, declared, counted, or derived, and both the effective and recorded times.
- A converted quantity identifies the conversion basis and version; the original measured value is never replaced by a converted value.
- The posting contract accepts optional opaque references to an operation execution, order or batch, and Work Centre/Resource. Stock stores them without needing those modules to be installed.
- Warehouse receipts, ordinary warehouse movements, and adjustments are open to any caller. A posting that carries production or transform context, including consumption against a production order, production output, and any transform, is accepted only from a registered posting authority.
- Only a Domain-layer module may register as an authority; an Extension's registration is refused, so Extensions submit production commands and imports through Manufacturing's execution/import contract. With no authority registered, production and transform postings are refused and warehouse use continues.
- Manufacturing validates production work and commits execution, Stock effects, and any required override evidence atomically.
- A retry with the same request does not create a duplicate. Two users cannot consume the same available quantity at once. Late entry preserves both effective and recorded times.
- A transform atomically commits all input effects, output creation, and
  genealogy. It preserves observed quantities and their provenance;
  accounting balance does not mean measurements agree. Any difference creates
  a mandatory variance record with its provenance and reconciliation basis.
  The system never changes an observed quantity to force agreement.
- Genealogy queries follow a lot or unit backward to its receipt and forward to descendant outputs. No caller stores a competing parent/child history.
- Tenant and company boundaries follow the platform's established scope rules; callers use the public API rather than passing raw ownership identifiers or writing Stock tables.

## Phases

### Inventory/Stock module

#### Phase 1 — Catalog, locations, and units

- [ ] Preserve the existing item master contract in the Stock module.
- [ ] Define stock locations, material identity, native units, and versioned item-level conversions.
- [ ] Expose public, scoped operations for catalog, location, unit, and stock-position reads.

Validation: a stock position can be read by item and location without a Manufacturing module.

#### Phase 2 — Material Transaction ledger

- [ ] Record receipt, transfer, consumption, output, and correction as balanced append-only transactions.
- [ ] Retain actor, source evidence, native quantity, timestamps, and any conversion basis.
- [ ] Make retries safe, prevent two users from consuming the same quantity, preserve late-entry times, and record corrections as new transactions.
- [ ] Accept and retain optional opaque context references through the posting contract.
- [ ] Add the posting-authority registry; refuse production or transform context from an unregistered caller and refuse registration from an Extension.
- [ ] Commit each transform's input effects, outputs, and genealogy atomically;
  retain observations unchanged and require a provenance-backed variance for
  every difference.

Validation: a measured 100 kg input can produce 78 kg of measured finished
material, 17 kg of derived trim, and 2 kg of measured waste, with the remaining
3 kg recorded as a variance and its evidence and reconciliation basis. The
accounting transaction balances without changing any observed quantity or
claiming measurement agreement. The transform is accepted only from a
registered posting authority.

#### Phase 3 — Material units and Lot/Unit Genealogy

- [ ] Identify lots and individual units where the handling process needs them.
- [ ] Link input identities to output identities for material transformations.
- [ ] Expose backward and forward genealogy reads from Stock's public contract.

Validation: a transformed output traces to its source receipt, and a receipt traces to its descendants.

#### Phase 4 — Standalone and cross-Domain proof

- [ ] Prove that catalog, ledger, stock-position, and genealogy operations work with Manufacturing absent.
- [ ] Prove that Manufacturing's execution/import contract can post actual production inputs and outputs to Stock with optional opaque context and atomic execution evidence.
- [ ] Add architecture tests proving that Stock does not depend on Manufacturing, that production and transform postings are refused with no authority registered, that a registered Manufacturing posting is accepted, and that an Extension cannot register or post production context.
- [ ] Validate the reusable contract against Mr Packaging Sdn Bhd and SBG as different examples, without putting their customer rules in Stock.

Validation: both examples reconcile from Stock transactions, and removing a caller does not change Stock's durable history.
