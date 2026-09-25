# docs/plans/factory/mr-packaging-requirements.md

**Status:** Proposed customer requirements
**Last Updated:** 2026-09-25
**Sources:**
- Client meeting notes, Mr Packaging Sdn Bhd, Muar LDPE foam plant (2026-08-15)
- [`docs/plans/factory/0000-factory-domain.md`](0000-factory-domain.md)
- [`docs/plans/factory/0010-inventory-module.md`](0010-inventory-module.md)
- [`docs/plans/domain-extension-layer-rollout.md`](../domain-extension-layer-rollout.md)
- [`docs/architecture/0010_composition-model.md`](../../architecture/0010_composition-model.md)
- [Pull request 800](https://github.com/BelimbingApp/bilimbi/pull/800)
- [Pull request 804](https://github.com/BelimbingApp/bilimbi/pull/804)

**Agents:** claude/claude-opus-5 (earlier work),
amp/medium-sol (architecture review only), codex/gpt-5 (earlier work),
codex/gpt-5.6-luna (earlier work), codex/gpt-6-luna-xhigh (earlier work), codex/gpt-6-sol-medium (Factory boundary revision),
claude/claude-opus-5.5 (no-mistakes review agent)

## Problem Essence

Manual material records do not let Mr Packaging Sdn Bhd explain the gap between what arrived, what production used, and what shipped. Mr Packaging Sdn Bhd manufactures LDPE foam in Muar, Johor. The requirements below are treated as candidate generic factory capabilities, with plant-specific values and workflow details confirmed during discovery.

- Supplier receipts, extrusion, cure, lamination, cutting, packing, and despatch are not connected by reliable material identity.
- Current records cannot separate short-weighted receipts, material loss, theft, trim, and waste using measured evidence.
- Foam rolls wait 7–10 days to cure, but their identity, location, and cure age are hard to confirm after the wait.
- Monthly production forecasts are not consistently tied to cut yield and finished stock.

## Desired Outcome

Mr Packaging Sdn Bhd can reconcile a representative month from supplier receipt to shipped pack with clear measurements and a light data-entry flow. As the first Factory build's validation case, it proves the shared modules and their configuration against a complete receipt-to-despatch workflow.

- A clerk records each lorry's declared and measured weight, including gross, tare, and net.
- An operator labels each foam roll and can find its location and cure age.
- Each production step records its input, output, product, trim, waste, and measurement source.
- A monthly view explains material balance and variance by supplier, run, operation, resource, location, and period.
- The current scope is expected to use Factory without a customer-specific Extension. Plant-specific products, process values, resources, labels, and permissions use Factory's public contracts; create an Extension only for a confirmed gap.

## Top-Level Components

This plan records what the Muar operation needs from [Factory](0000-factory-domain.md). Its Inventory module contract is detailed in [`0010-inventory-module.md`](0010-inventory-module.md).

- **Inventory module** — records item and location, native quantity and unit, declared or measured evidence, roll identity, warehouse movements, production effects, and ancestry. Warehouse receipts and ordinary warehouse movements post directly through Inventory.
- **Product Definition and Production Execution modules** — Product Definition defines the foam products, routings, and cure minimum. Production Execution records actual extrusion and conversion work, enforces the cure hold, and presents production trace over Inventory genealogy. Production commands and history imports use its contract; it posts Inventory effects atomically with execution and any required override evidence.
- **Mr Packaging configuration and validation** — supplies the plant's confirmed products, process values, locations, resources, labels, and permissions to Factory. An Extension is expected to be unnecessary; add one only for a proven customer-specific gap.

## Customer Requirements

### Receiving and weighing

The receiving flow needs to show what the supplier declared and what the plant measured.

- Supplier, lorry or vehicle, material, receiving location, date, and clerk.
- Supplier-declared weight and measured gross, tare, and net weight.
- Native weight unit, source of each value, and the difference between declared and measured quantity.
- A receipt remains identifiable when material moves from receiving to storage or production.

### Blend and extrusion

The extrusion record needs to identify the blend and each resulting roll.

- Virgin resin and roughly 30% recycled material, subject to confirmation at the plant.
- Three fixed foam colours, the extruder, production run, date and time, and the selected recipe and routing.
- One identity for each roll, with measured width, thickness, and length.
- Inputs, output quantities, and any measured or reported variance.

### Cure and roll handling

A roll's production time must remain available while it waits for the next step.

- Record where each roll is stored and when it was produced.
- Show elapsed cure age against the configured minimum, which is expected to be within a 7–10 day window and must be confirmed by product.
- Refuse under-cured consumption by default. An authorised override needs an explicit Base Authz capability and a mandatory reason, and keeps actor, time, reason, and affected roll as an immutable record.
- Keep cure duration and process gates as Factory configuration; do not create `MrPackaging` code for values or rules the shared configuration can express.

### Lamination, cutting, packing, and despatch

Conversion records need to account for both saleable output and the material that did not become product.

- Link input rolls to lamination and cutting work, including the demand source and target width.
- Record actual product, trim or offcut, waste, operator, and yield.
- Keep monthly forecast as an opaque demand-source reference on the production order; confirm it before building order matching or backlog assumptions.
- Record finished-pack identity, quantity and unit, with destination and shipment as opaque references on the terminal Inventory movement.
- A known 1200 mm input cut to 800 mm should show product, trim, waste, and attributable yield.

### Reconciliation and trace

Monthly reports need to explain the material balance without replacing Factory Inventory's material account.

- Compare expected and actual input, output, product, trim, waste, and stock by supplier, operation, run, resource, location, and period.
- Separate measured, declared, counted, and derived quantities; show the conversion basis used for any normalised mass.
- Preserve every observed quantity. When a transformation's measured and derived quantities differ, record a mandatory variance with its source evidence and reconciliation basis; a balanced ledger does not imply that measurements agree.
- Show the affected receipt, roll, run, or finished pack for each unexplained variance.
- Trace a shipped pack backward to its roll, production run, and supplier receipt; trace a receipt forward to its descendants.
- Retain original records. A correction is a new compensating movement with a reason, not an edit or delete.

## Design Decisions

### Identify every roll

Cure age and cut yield attach to individual rolls, not just to an extrusion run.

- **Option A — identify only the production run:** fewer labels, but staff cannot distinguish rolls with different locations, cure times, or yields.
- **Option B — give every roll a durable label:** adds a scan at roll handling, but supports storage, cure, and conversion trace.
- **Option C — automate identification with RFID or line sensors:** reduces scanning, but requires equipment and plant coverage before the workflow is proven.
- **Recommendation — Option B:** use a replaceable barcode label first; validate that it survives the 7–10 day cure and normal handling.

## Public Contract

Mr Packaging Sdn Bhd needs Factory to support these customer-facing results.

- Receiving captures supplier, vehicle, material, location, actor, date, declared weight, measured gross/tare/net, and variance.
- Production captures blend, colour, extruder, run, time, and each roll's measured dimensions.
- Roll handling shows identity, location, age, configured cure minimum, and any authorised override.
- Conversion captures input rolls, an opaque demand-source reference, target width, product, trim, waste, operator, and yield.
- Despatch captures pack identity, quantity, unit, and material movement with opaque destination and shipment references.
- Warehouse receipts and ordinary warehouse movements post through Inventory; extrusion and other production commands or production-history imports use Production Execution's contract so the execution and Inventory effects commit together.
- A transform preserves measured input and output values, and records any difference as a provenance-backed variance rather than altering observations.
- Reconciliation reports by operation, execution, supplier, resource, location, period, and order or batch when one exists.
- A retry does not duplicate a movement, two users cannot consume the same available quantity, late entry preserves effective and recorded times, and correction adds a new transaction with a reason.
- Missing measurements stay visibly unknown; the application does not present a derived value as measured evidence.

## Phases

### Inventory module

#### Phase 1 — Receiving and weighing

- [ ] Confirm where weighing happens and which clerk records supplier, vehicle, material, and location.
- [ ] Confirm weight units and capture declared weight plus measured gross, tare, and net.
- [ ] Post one representative lorry receipt through Inventory and show the supplier variance.
- [ ] Keep the receipt traceable as it moves into storage or production.

Validation: a clerk records a lorry in one flow and can explain the source of every recorded weight.

#### Phase 2 — Roll labels and storage locations

- [ ] Confirm label material, placement, survivability, and network coverage at the plant.
- [ ] Set up the cure-storage locations and the unit identity that roll labels will carry.
- [ ] Prove a test label can be scanned and moved between locations as an ordinary warehouse movement.

Validation: a labelled unit can be located through Inventory after a physical move, without any production posting.

### Product Definition and Production Execution modules

#### Phase 3 — Blend, extrusion, and cure

- [ ] Confirm blend proportions, colours, measured dimensions, and applicable cure minimum with plant staff.
- [ ] Configure foam process families, routes, output roles, conversion bases, and cure gates as Factory data.
- [ ] Record an extrusion execution that consumes the received material and creates each labelled roll with its identity, production time, and dimensions.
- [ ] Prove that each roll traces to its input receipt through Inventory genealogy and can be located after the physical cure delay.
- [ ] Verify the default hold for under-cured material and the authorised override evidence.
- [ ] Keep this workflow in Factory when the confirmed process fits its public contracts and configuration; document a concrete gap before proposing an Extension.

Validation: an operator can identify each roll, trace it to its receipt, see its cure age, and explain any consumed under-cured roll.

#### Phase 4 — Lamination, cutting, packing, and despatch

- [ ] Confirm the demand source before building matching; do not assume sales-order backlog.
- [ ] Configure lamination, cutting, packing, and despatch routes and resources.
- [ ] Record product, trim/offcut, and waste as identified outputs and report yield per roll and run.
- [ ] Trace a finished pack to its roll and receipt, then trace the receipt forward.

Validation: the known 1200 mm to 800 mm cut and a representative shipment reconcile to identified material.

#### Phase 5 — Monthly reconciliation and customer acceptance

- [ ] Report expected and actual quantities by supplier, operation, resource, location, and period.
- [ ] Separate measured differences from derived-measurement uncertainty and show each unexplained discrepancy.
- [ ] Verify duplicate-safe retries, concurrent consumption, late entry, reversal, tenant scope, and append-only correction.
- [ ] Confirm the requirements against Factory's contracts and configuration; document a specific gap before proposing any Extension code.
- [ ] Confirm a representative month with the customer and retain the source evidence for each reported total.

Validation: Mr Packaging Sdn Bhd can reconcile a representative month and carry each unresolved difference as an open investigation.

## Open Assumptions

- Selling and packing units remain unconfirmed for pricing; they do not block native measurements in the ledger.
- Label survivability, weighing locations, network coverage, demand source, and certification scope need on-site validation.
- AutoCard is assumed replaced rather than integrated; confirm this before any import or synchronization work.
- Paper or spreadsheet weigh tickets and cut-yield records may provide known examples during rollout.
- This plan supports evidence and traceability; it does not claim ISO 9001, ISO 14001, ISO 45001, or customer certification.
