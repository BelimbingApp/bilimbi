# docs/plans/commerce-material-flow-ledger.md

**Status:** Proposed
**Last Updated:** 2026-09-25
**Sources:** Client meeting notes, LDPE foam plant (2026-08-15);
`docs/architecture/0010_composition-model.md`;
`docs/plans/domain-extension-layer-rollout.md`;
`docs/PORTING_STAGES.md` (S5); `AGENTS.md` §"Future Domains and
Extensions", §5 schema compatibility; Belimbing
`app/Domains/Commerce/Inventory` (item master, 3 models);
material-flow scout report (2026-09-25), with the accepted decision to use a
generic Manufacturing / Production Operations Domain and extensions for
customer-specific behaviour
**Agents:** claude/claude-opus-5, amp/medium-sol

## Problem Essence

An LDPE foam plant runs its entire material flow on manual records, so no step records what came in against what went out and the mass balance never closes. Loss, theft, supplier short-weighting, and cutting waste are all invisible in the same way: there is no pair of numbers to compare.

## Desired Outcome

Every material step records observed input and output in its native unit with provenance, plus a normalised mass equivalent for reconciliation, so discrepancies surface as attributable numbers rather than suspicions. The plant can answer what arrived from each supplier, what entered and left each production step, how much became product or trim, and what is physically in stock. Append-only, attributable records support audit evidence without claiming that this plan alone satisfies any certification.

## Context that shapes the design

The plant extrudes LDPE foam for packaging in three fixed colours, blending roughly 30% recycled material with virgin resin. Material passes through extrusion, a 7–10 day cure, lamination, cutting to width, packing, and shipping. Two extruders run 24 hours, typically five days at a stretch, then stop when finished goods have nowhere to go. Production runs to a monthly forecast rather than to order.

Three facts constrain the design more than any feature request:

- **Units change shape at every step.** Material arrives as weight, becomes geometry as rolls, and leaves as counted pieces. Reconciliation is impossible without a recorded conversion basis; this is the central modelling problem, not the scanning.
- **Labour is the binding constraint.** The plant cannot reach higher certification because it lacks people, and one new hire is the entire capacity for driving this. Any capture step that is not one scan plus at most one number will be abandoned.
- **Identity must survive ten days of cure.** A roll sits for 7–10 days between production and its next step, so its label is a physical object in a dusty plant, and cure age is itself a production rule.

## Top-Level Components

- **Inventory / Stock** — one global append-only material-flow ledger over identified material units, locations, quantities, and balanced transactions. A per-station ledger is only a filtered view of this ledger, never a second store of truth.
- **Lot and unit identity** — durable identity for a bag, a roll, or a pack, with parent/child links across transforms so a finished pack traces back to an extruder run and to a recycle receipt.
- **Receiving and weigh tickets** — supplier, vehicle, gross/tare/net, tied to the movement that creates the lot.
- **Manufacturing / Production Operations** — operation definitions and executions for extrusion, cure, lamination, coating, slitting, cutting, packing, and other configured process families. The first implementation is the Production module, with `product_definition`, `process_definition`, `execution`, and `trace` as internal boundaries until a real selection need justifies separate modules.
- **Cut planning and trim accounting** — matching measured roll widths to widths from the confirmed demand source, with offcut recorded as an explicit output.
- **Capture surface** — printed labels and scanning, plus the small number of manual measurements that cannot be automated.
- **Reconciliation reporting** — expected against actual per operation, execution, supplier, order or batch, resource, and location.

## Model and naming

The stable business model is a generic **Manufacturing / Production Operations
Domain**, not a sheet-goods Domain. It holds common, industry-neutral logic;
generality is earned from the Muar LDPE foam plant and SBG adhesive-tape case,
not from speculative abstractions.

The canonical names are **Inventory/Stock**, **Manufacturing/Production**,
**Product Definition**, **Formula/BOM**, **Routing**, **Operation**, **Work
Centre/Resource**, **Production Order**, **Batch**, **Operation Execution**,
**Material Transaction**, **Lot/Unit Genealogy**, **Quality**, **Planning**,
and **Costing**. Optional UI labels may be **Flow**, **Make**, **Blueprint**,
**Route**, **Run**, and **Trace**. Reserve **Material Ledger** for a future
valuation capability; the operational record here is the Material Transaction
ledger.

Definitions are separate from execution facts. Product Definition,
Formula/BOM, and Routing describe what may be made and how. Operation is the
logical step; Work Centre/Resource is the physical machine, line, station, or
other capacity that performs it. Production Order and Batch provide planning
and execution context. Operation Execution records what actually happened and
tags its Material Transactions with the execution, source and destination
locations, order or batch, and Work Centre/Resource.

One global ledger is the source of truth. “Per-station ledger”, “per-order
ledger”, and similar screens are filtered views grouped by execution, location,
order or batch, and resource. They must not create parallel balances or
genealogy.

Variation is layered deliberately: plant differences are configuration and
data first — process families, route templates, units of measure, conversion
bases, tolerances, and output roles. An Extension is for customer-specific
behaviour that consumes public Domain contracts, such as AX integration,
customer vocabulary, or SBG's proprietary jumbo-roll costing. The Muar foam
plant uses the common Production logic with foam process-family and route
configuration; SBG uses the same logic with adhesive-tape, coating, and
slitting configuration. No customer-specific calculation is pushed into the
common Domain merely because two plants both manufacture.

Quality, Planning, and Costing remain related capabilities with explicit
contracts to the Domain rather than hidden fields in the ledger. ISO 9001,
ISO 14001, and ISO 45001 requirements are later capabilities around this
ledger: Quality; Document/Change Control; Metrology/Calibration;
records/audit; supplier quality; and EHS. IATF 16949 is added only when an
automotive customer requires it. The ledger alone does not claim certification
compliance.

## Design Decisions

### Quantity model

**Option A — mass only.** Every movement is recorded in kilograms; geometry (width, thickness, length) is an attribute of the unit, and area or piece counts derive from a recorded density per formulation. Reconciliation is arithmetic on a single unit end to end, but inferred mass becomes indistinguishable from observed mass.

**Option B — geometry only.** Movements are recorded in area or linear metres, with mass as an attribute. This matches rolls and cuts but makes weight-based receiving and blending depend on reverse conversions.

**Option C — native observations plus normalised mass.** Record the observed quantity in its native unit, how it was obtained, the versioned conversion basis, and a normalised mass equivalent. This preserves measurement truth while providing one reconciliation basis.

**Recommended: C.** Mass remains the reconciliation basis but never appears as an observed fact when it was derived. A roll captured as width, thickness, and length has an inferred mass; its variance therefore reflects density assumptions and measurement error as well as possible material loss.

Every quantity therefore records four things: the **native observed quantity and unit**, how it was obtained — **measured, declared, counted, or derived** — the **conversion basis and its version** where one was applied, and a **normalised mass equivalent** for reconciliation. Mass stays the basis on which the plant's books balance; provenance is what makes a variance report worth reading, because a discrepancy traceable to derived quantities is a measurement problem and a discrepancy between two measured quantities is a material problem.

This also makes the plant's selling unit largely irrelevant to the ledger, which removes the dependency that previously blocked Phase 1.

### Module ownership

The Manufacturing / Production Operations Domain owns the common logic and
public contracts for definitions, operations, executions, material
transactions, and genealogy. Production is the first module; its internal
boundaries are `product_definition`, `process_definition`, `execution`, and
`trace`. Keep them internal until a real customer needs independent module
selection or ownership. Inventory/Stock remains a related capability with its
own public contract; it does not need to know manufacturing semantics.

The Domain is selected as one cohesive capability. Foam, adhesive tape, web
coating, and slitting are process families and route configuration, not stable
Domains. An Extension is introduced only for a real customer-specific
adaptation: for example AX integration or vocabulary mapping for a customer,
or SBG's proprietary jumbo-roll costing. Extensions consume public contracts
and never reach into Product Definition, Routing, Execution, or ledger
internals. This gives one high-level abstraction with common logic while
keeping customization out of the common model.

### Configuration ownership

Configuration is not a Domain of its own. Each Domain owns the meaning of its
configuration: Manufacturing owns process families, route templates,
operations, output roles, and process parameters (the Blueprint/Route
definitions); Inventory owns items, locations, and lot rules. The generic
per-company settings mechanism remains in Base Settings
(`apps/base/settings`), while shared units of measure are an Inventory (or
Base) concern rather than a Manufacturing concern. Extensions may consume
both Domain contracts and Base Settings, but do not turn configuration into a
parallel business layer.

### Capture mechanism

**Option A — barcode labels and handheld scanners.** Cheap, printable on site, replaceable when damaged, and every touchpoint here already has a person handling one unit at a time.

**Option B — RFID.** Earns its cost with bulk or no-line-of-sight reads. Neither applies: material moves unit by unit through human hands. Tag cost per roll is material given the volumes, and the plant environment is flammable-rated, which complicates reader placement.

**Option C — infrared width scanning at the extruder.** Removes one manual measurement, and was raised in the meeting. It is a capital purchase solving the smallest part of the width problem; the loss comes from cutting the wrong widths, not from mis-measuring them.

**Recommended: A, with C explicitly deferred.** Barcode plus a typed measured width at extruder output captures nearly all the available value at nearly no capital cost. Automatic width measurement becomes worthwhile only once the cut planning it feeds is proven to work.

### Roll identity granularity

Label each roll individually rather than labelling the run. Per-roll identity is what makes cutting yield computable, since yield is a property of a roll's measured width against what was cut from it, and it is the only way a ten-day cure gate can be enforced per unit. A run-level label would collapse exactly the distinction the plant is losing money on.

## Public Contract

- Movements are append-only. Corrections are compensating movements carrying a reason and a reference to what they correct; nothing is deleted or edited in place. This supports audit evidence; whether it satisfies a particular certification depends on controls this plan does not yet cover — authorisation, timestamp integrity, correction procedure, retention, backup, calibration, and record review — so no claim is made that append-only records alone are ISO evidence.
- **The transaction, not the movement, is the unit of record.** A transaction is immutable and contains balanced entries naming both source and destination; a movement that names one location cannot establish conservation or a stock position. Nothing is written as a lone half-entry.
- Every entry names its operation execution, material unit, native quantity and unit, provenance, source and destination locations, order or batch where applicable, Work Centre/Resource where applicable, actor, and tenant. The Operation remains the logical step; the Work Centre/Resource identifies the physical performer.
- A transform consumes input units and produces output units in one transaction, linking parent to child. A transform that does not balance within a configured tolerance is recorded together with its variance rather than rejected — the plant must be able to record reality, and an unexplained variance is the product, not an error to suppress.
- The ledger states its behaviour for **idempotent submission** (a re-sent capture does not double-post), **concurrent consumption** (the same quantity cannot be consumed twice), **backdating** (an entry recorded late carries both its effective and recorded times), and **reversal** (a compensating transaction, never a delete). These are contract, not implementation detail.
- Trim and waste are output units with their own identity, not an unrecorded difference between input and output.
- Lot ancestry is queryable in both directions: from a shipped pack back to its recycle receipts, and from a supplier receipt forward to everything it became.
- Inventory/Stock exposes no private manufacturing implementation. Manufacturing reaches it only through public contracts, while the global transaction ledger remains the single source of truth for all stations and operations.
- Manufacturing is industry-neutral. Cure duration, tolerance, route steps, units of measure, conversion bases, and output roles are configuration and data. Foam, adhesive tape, web coating, and slitting are process-family or route choices, not hardcoded branches.
- Definitions (Product Definition, Formula/BOM, and Routing) are not execution facts. Execution records actual quantities, resources, locations, timings, variances, and genealogy while preserving the selected definition and route context.
- The Domain may be installed without any customer Extension. Muar foam and SBG tape behaviour remains expressible through configuration until a public-contract-consuming customer adaptation is proven necessary.
- Cure gating refuses under-aged consumption by default. An override requires an explicit Base Authz capability and a mandatory reason, and records the actor, time, reason, and affected unit as an immutable nonconformance.

## Phases

Phase 1 is a vertical slice deliberately narrower than the substrate beneath it. An earlier draft built a general transform ledger with bidirectional ancestry before the plant saw anything, which risks constructing a manufacturing substrate before adoption is validated. Receiving is the highest-value, lowest-dependency workflow: it needs nothing upstream of itself and it addresses the loss the plant can measure today.

### Phase 1 — Receiving, end to end

Goal: a receiving clerk records an arriving lorry in one screen, and a supplier's history of declared against measured weight is visible without further work.

- [ ] Port Belimbing's canonical item master into the stock module, preserving
  its schema under `AGENTS.md` §5.
- [ ] Establish durable receiving and warehouse locations used by receipts and stock positions.
- [ ] Record weigh tickets with supplier, vehicle, gross, tare, and net.
- [ ] Capture declared weight alongside measured weight so the difference is a stored fact, each carrying its provenance.
- [ ] Post receipts as balanced immutable transactions, in the shape Phase 2 generalises rather than a shape it will replace.
- [ ] Show a received stock position by material and location.
- [ ] Report per-supplier declared-versus-measured variance over time.

Assumptions: Inventory/Stock and the Manufacturing / Production Operations
Domain are mounted through the composition model before this slice is built;
Production is the first Manufacturing module and its internal boundaries are
not independently selectable yet.
Validation: variance report over seeded receipts with known discrepancies; a clerk completing a real lorry in one screen.

Deferred from this phase: landed recycle cost against virgin resin. It needs purchase price, currency, freight, and possibly duty — none of which any module owns yet. Valuable, but it is a costing feature wearing a receiving disguise.

### Phase 2 — Ledger foundation

Goal: any step's input and output can be recorded as one balanced transaction, and a stock position or lot ancestry can be read back, with no manufacturing concept present in the module.

- [ ] Add material unit identity with parent/child ancestry across transforms.
- [ ] Extend locations from receiving and warehouse into WIP, cure, and finished goods.
- [ ] Generalise Phase 1's receipts into transactions of balanced entries carrying native quantity, unit, and provenance.
- [ ] Add the transform operation consuming inputs and producing outputs in one transaction, recording variance.
- [ ] Implement the contract's idempotency, concurrent-consumption, backdating, and reversal behaviour.
- [ ] Expose stock position and lot ancestry as public read models.

Validation: tenant boundary, append-only enforcement, ancestry traversal, and double-consumption tests; `mix precommit` green.

### Phase 3 — Roll identity, extrusion, and the process module

Goal: every roll leaving an extruder carries a scannable label recording its measured width, thickness, and production date, and that label still resolves after ten days in cure.

- [ ] Mount the Manufacturing / Production Operations Domain under `apps/` with its first Production module and declared dependency on Inventory/Stock's public contract. Extrusion output and blend composition belong in Production, not in Inventory/Stock.
- [ ] Create roll units at extrusion output with measured width, thickness, and length, each recorded as measured rather than derived.
- [ ] Generate and print barcode labels carrying the durable unit identity and production date.
- [ ] Scan-to-locate: resolve a scanned label to its unit, location, and cure age.
- [ ] Record blend composition per extruder run, including recycle proportion.

Risks: label survivability over a 7–10 day cure in plant conditions is a physical unknown; trial on a small run before the process depends on it.

### Phase 4 — Demand source, then cut planning

Goal: a cutting operator is shown which demand a given roll should serve, and every millimetre of that roll is accounted for as product or as trim.

- [ ] Establish where demand comes from before building any matching: sales orders, monthly forecast lines, manual cutting batches, or finished-goods replenishment targets. The plant runs to monthly forecast rather than to order, so "outstanding ordered widths" is not a source that exists — an earlier draft assumed it did.
- [ ] Record cut output units and trim units as explicit outputs of one transaction.
- [ ] Report yield per roll, per run, and per operator.
- [ ] Propose a cut plan against the demand source established above.
- [ ] Flag rolls cut materially below their achievable yield.

Goal note: the meeting's example — a 1200mm roll cut to 800mm, losing a third — should appear as a specific, attributable number. Yield reporting is useful before planning exists, so it is ordered first.

### Phase 5 — Cure gating, lamination, and despatch

Goal: an under-cured roll cannot be consumed by accident, and can be consumed deliberately with the reason recorded.

- [ ] Warn and refuse by default when a roll is below the configured minimum cure age.
- [ ] Allow an authorised override carrying a mandatory reason, retained as a nonconformance record. A hard block invites bypass: if production physically proceeds anyway, an absolute refusal teaches operators to work around the system and the records stop describing reality.
- [ ] Record lamination as a transform combining rolls into a laminated unit.
- [ ] Record packing into finished-goods units with their sales identity.
- [ ] Record despatch as the terminal transaction.

### Phase 6 — Reconciliation

Goal: a monthly reconciliation shows input, output, and accounted loss per step, separating material loss from measurement error.

- [ ] Per-step expected-against-actual reconciliation across a date range.
- [ ] Split variance by provenance, so a discrepancy between measured quantities reads differently from one involving derived quantities.
- [ ] Unexplained variance report ranked by magnitude.
- [ ] Lot traceability report from despatch back to receipts.
- [ ] Density per formulation maintained as reference data with change history and versioned conversion bases.

## Open Assumptions

Work proceeds on these unless corrected; each is recorded because being wrong about it changes the design rather than the schedule.

- **Selling unit is unconfirmed, and no longer blocking.** Recording native quantity plus provenance, with mass as the reconciliation basis, means the plant's pricing unit does not decide the ledger's shape. It still needs confirming for pricing and packing.
- **Site validation is outstanding.** Label survivability, where weighing actually happens on the floor, network coverage at each capture point, the real demand source, and the applicable certification requirements all need checking on site before Phases 3 to 6 are committed to.
- **Extension boundary is intentionally unpopulated.** Plant variation is configuration and data first. Muar foam and SBG tape are the two grounding cases; AX integration, customer vocabulary, and SBG jumbo-roll costing are examples of later Extensions if their public-contract seams are needed.
- **Stable names are now chosen.** The Domain is Manufacturing / Production Operations, with Production first and `product_definition`, `process_definition`, `execution`, and `trace` internal boundaries. Inventory/Stock owns the related stock capability. Repository selection does not remove the cost of renaming stable module and OTP application identities later.
- **AutoCard is assumed to be replaced, not integrated.** No import or synchronisation work is planned. If it must survive, an integration phase is added and Phase 2 changes shape.
- **Interim manual process.** The plant has no system until the composition proof passes and Inventory/Stock's receiving slice is available. A paper or spreadsheet weigh-ticket and cut-yield discipline started now would both deliver value immediately and produce a data shape to validate Phases 2 and 4 against. This is a client-side decision recorded here so it is not lost.

## Revision notes

- **2026-09-25** — Adopted the material-flow scout recommendation and the
  accepted decision: one global balanced, append-only Material Transaction
  ledger with filtered per-operation or per-station views; explicit separation
  of Operation from Work Centre/Resource and definitions from execution;
  generic Manufacturing / Production Operations with Production first;
  process-family and route configuration for Muar foam and SBG tape;
  Extensions for customer-specific behaviour; canonical and UI naming; and a
  later ISO capability set around the ledger. Source: material-flow scout
  report and the resulting launch decision.
