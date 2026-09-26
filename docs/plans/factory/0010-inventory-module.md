# docs/plans/factory/0010-inventory-module.md

**Status:** Proposed
**Last Updated:** 2026-09-25
**Sources:**
- [`docs/plans/factory/0000-factory-domain.md`](0000-factory-domain.md)
- [`docs/plans/factory/mr-packaging-requirements.md`](mr-packaging-requirements.md)
- [`docs/plans/domain-extension-layer-rollout.md`](../domain-extension-layer-rollout.md)
- [`docs/architecture/0010_composition-model.md`](../../architecture/0010_composition-model.md)
- [`AGENTS.md`](../../../AGENTS.md) §§4–6
- Belimbing `app/Domains/Commerce/Inventory` item master and models
- [Pull request 800](https://github.com/BelimbingApp/bilimbi/pull/800)
- [Pull request 804](https://github.com/BelimbingApp/bilimbi/pull/804)

**Agents:** codex/gpt-5.6-luna (earlier work), codex/gpt-6-luna-xhigh (earlier work), codex/gpt-6-sol-medium (Factory boundary revision),
claude/claude-opus-5.5 (earlier review)

## Problem Essence

Material records cannot be trusted when receipts, use, transformations, and adjustments live in separate balances. Factory Inventory must give every factory workflow one account of material and its history.

- Separate ledgers for receiving, production, and work areas can disagree about the same material.
- A balance alone cannot explain which receipt or earlier lot produced an output.
- Changing a quantity in place hides what happened and who corrected it.
- Material records tied only to production cannot support receiving and warehouse work.

## Desired Outcome

Factory Inventory owns items, locations, units of measure, material transactions, and Lot/Unit Genealogy as a module in the Factory Domain. Production Execution posts material changes through its public contract and reads the same history.

- One append-only Material Transaction ledger records every movement, receipt, use, output, and correction.
- Current stock positions are views over that ledger, not a second source of truth.
- Lot/Unit Genealogy links the input and output lots or individually identified units of each transformation, so a receipt can be traced forward to its descendants and an output backward to its source.
- Each transaction keeps its original quantity and unit, evidence source, and any conversion basis used for reporting.
- Callers may attach optional opaque context references without making Inventory depend on their business meaning.
- The same contract supports factory receiving, storage, and production.
- Production and transform postings come only from a registered posting authority, so no caller can skip the production rules that authority enforces.

## Top-Level Components

Inventory is one Factory module with these related responsibilities:

- **Item and material records** — identify stockable materials and products while preserving the existing item master contract.
- **Locations and stock position** — record where material is held and present the current position by item, location, lot, and unit.
- **Units of measure and conversions** — preserve each item's native unit and the versioned basis for a converted quantity.
- **Material Transaction ledger** — keep balanced, append-only records for receipts, transfers, consumption, outputs, and new correction transactions that refer to what they correct.
  “Material Ledger” is reserved for future valuation; the operational record is the Material Transaction ledger.
- **Material units and Lot/Unit Genealogy** — identify lots or individual units and link inputs to outputs when a material transformation occurs.
- **Posting and query contract** — let other modules record and read material facts without using Inventory's tables or private queries.
- **Posting-authority registry** — records which module in Inventory's Domain container may post production or transform context. Inventory names no registrant and does not depend on Production Execution.

Production Execution supplies optional execution, order or batch, and Work Centre/Resource references when it posts. Inventory stores those references as opaque context; it does not resolve or interpret them. Production Execution registers as Inventory's posting authority. See [`0000-factory-domain.md`](0000-factory-domain.md) for the Domain map.

## Design Decisions

### Accept production postings only from a registered authority

Production Execution owns configured production rules, but Inventory records the material effect. Inventory must refuse a production posting that skipped those rules without depending on Production Execution.

- **Option A — trust callers and rely on review:** no new seam, but an Extension can post production usage straight to Inventory and nothing refuses it.
- **Option B — gate production postings behind a Base Authz capability:** reuses authorization, but capabilities belong to people, so any caller acting for a privileged user still bypasses Production Execution.
- **Option C — an Inventory-owned posting-authority registry:** Inventory refuses production or transform context unless the posting comes from a registered module in its Domain container, as declared by composition metadata. Production Execution registers first; Extensions cannot register.
- **Recommendation — Option C:** Inventory enforces the boundary while Production Execution owns production validation.

## Public Contract

The public contract makes each quantity and its history explainable.

- A Material Transaction is append-only, attributable, and balanced across its source and destination effects. A correction adds a new transaction with a reason and a reference to the original; it never edits or deletes the old record.
- Every entry retains its native quantity and unit, whether it was measured, declared, counted, or derived, and both the effective and recorded times.
- A converted quantity identifies the conversion basis and version; the original measured value is never replaced by a converted value.
- The posting contract accepts optional opaque references to an operation execution, order or batch, Work Centre/Resource, shipment, and destination. Inventory stores them without interpreting their business meaning.
- Warehouse receipts, ordinary warehouse movements, and adjustments are open to any caller. A posting that carries production or transform context, including consumption against a production order, production output, and any transform, is accepted only from a registered posting authority.
- Only a module in Inventory's own Domain container, as declared by composition metadata, may register as a production posting authority; Production Execution is the initial registrant. Inventory names no registrant and depends on none. An Extension's registration is refused, so it submits production commands and imports through Production Execution's public contract. With no authority registered, production and transform postings are refused and warehouse use continues.
- Production Execution validates production work and commits execution, Inventory effects, and any required override evidence atomically.
- A retry with the same request does not create a duplicate. Two users cannot consume the same available quantity at once. Late entry preserves both effective and recorded times.
- A transform atomically commits all input effects, output creation, and
  genealogy. It preserves observed quantities and their provenance;
  accounting balance does not mean measurements agree. Any difference creates
  a mandatory variance record with its provenance and reconciliation basis.
  The system never changes an observed quantity to force agreement.
- Genealogy queries follow a lot or unit backward to its receipt and forward to descendant outputs. No caller stores a competing parent/child history.
- Tenant and company boundaries follow the platform's established scope rules; callers use the public API rather than passing raw ownership identifiers or writing Inventory tables.

## Phases

### Inventory module

#### Phase 1 — Catalog, locations, and units

- [ ] Preserve the existing item master contract in the Inventory module.
- [ ] Define stock locations, material identity, native units, and versioned item-level conversions.
- [ ] Expose public, scoped operations for catalog, location, unit, and stock-position reads.

Validation: a stock position can be read by item and location without invoking Production Execution.

#### Phase 2 — Material Transaction ledger

- [ ] Record receipt, transfer, consumption, output, and correction as balanced append-only transactions.
- [ ] Retain actor, source evidence, native quantity, timestamps, and any conversion basis.
- [ ] Make retries safe, prevent two users from consuming the same quantity, preserve late-entry times, and record corrections as new transactions.
- [ ] Accept and retain optional opaque context references through the posting contract.
- [ ] Add the posting-authority registry; refuse production or transform context from an unregistered caller and refuse registration outside Inventory's Domain container.
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
- [ ] Expose backward and forward genealogy reads from Inventory's public contract.

Validation: a transformed output traces to its source receipt, and a receipt traces to its descendants.

#### Phase 4 — Factory integration proof

- [ ] Prove that catalog, ledger, stock-position, and genealogy operations work without invoking Production Execution.
- [ ] Prove that Production Execution's contract posts actual inputs and outputs to Inventory with optional opaque context and atomic execution evidence.
- [ ] Add architecture tests proving that Inventory does not depend on Production Execution, that production and transform postings are refused with no authority registered, that a registered Production Execution posting is accepted, and that an Extension cannot register or post production context.
- [ ] Validate the reusable contract against distinct factory workflows without putting customer process rules or source mappings in Inventory.

Validation: distinct factory workflows reconcile from Inventory transactions without changing Inventory's durable history. The customer sequence is in the [rollout plan](../domain-extension-layer-rollout.md).
