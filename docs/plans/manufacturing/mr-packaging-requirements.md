# docs/plans/manufacturing/mr-packaging-requirements.md

**Status:** Proposed customer requirements
**Last Updated:** 2026-09-25
**Sources:**
- Client meeting notes, Mr Packaging Sdn Bhd, Muar LDPE foam plant
  (2026-08-15)
- [`docs/plans/manufacturing/manufacturing-domain.md`](manufacturing-domain.md)
- [`docs/plans/domain-extension-layer-rollout.md`](../domain-extension-layer-rollout.md)
- [`docs/architecture/0010_composition-model.md`](../../architecture/0010_composition-model.md)
- [`AGENTS.md`](../../../AGENTS.md) §4, §5, §6
- Belimbing `app/Domains/Commerce/Inventory` (item master, 3 models)
- Material-flow scout report (2026-09-25)

**Agents:** claude/claude-opus-5, amp/medium-sol, codex/gpt-5,
codex/gpt-5.6-luna (Luna-6, dispatched by firstmate; reviewed by the
no-mistakes pipeline)

## Problem Essence

Manual records never close the mass balance, so loss, theft, short-weighting,
and cutting waste cannot be told apart. Mr Packaging Sdn Bhd manufactures LDPE
foam in Muar, Johor.

- Manual records do not connect supplier receipts, extrusion, cure, lamination,
  cutting, packing, and despatch.
- The company cannot distinguish supplier short-weighting, material loss, theft,
  and cutting waste with measured evidence.
- A roll sits for 7–10 days before its next step, but its identity and cure age
  are not reliably carried through that delay.
- Production runs to a monthly forecast, while the records do not consistently
  connect the forecast, cut yield, and finished stock.

## Desired Outcome

Mr Packaging Sdn Bhd should be able to explain every material gap from a
supplier receipt to a shipped pack without adding a heavy data-entry burden.

- A receiving clerk records one lorry with declared and measured weight.
- An operator labels each roll and can resolve its location and cure age after
  the 7–10 day cure.
- Each step records native quantities and provenance, including product, trim,
  waste, and finished packs.
- A monthly report reconciles input, output, stock, and variance by supplier,
  run, operation, resource, location, and period.
- The common Domain remains reusable; `MrPackaging` contains only proven
  customer-specific behaviour.

## Top-Level Components

These components describe the Muar workflow and the customer evidence it needs.

- **Receiving and weighing** — supplier, lorry, gross, tare, declared weight,
  measured weight, net, material, location, actor, and variance.
- **Blend and extrusion** — virgin resin, roughly 30% recycled material, three
  fixed foam colours, extruder, run, recipe/configuration reference, date/time,
  and roll dimensions.
- **Roll identity and cure** — one durable label per roll, production time,
  current location, minimum cure duration, and an authorised override trail.
- **Lamination and cutting** — input rolls, laminated output, demand source,
  target width, product output, trim/offcut, waste, operator, and yield.
- **Packing and despatch** — finished-pack identity, quantity and unit,
  destination or shipment, and terminal movement.
- **Reconciliation and trace** — supplier variance, operation yield, stock
  position, and forward/backward ancestry.
- **`MrPackaging` Extension** — customer vocabulary, integration, calculation,
  alert, approval, or report only when the generic public contracts and
  configuration cannot express it.
- **Generic boundary** — the one ledger, Lot/Unit Genealogy, units of measure,
  context references, definitions, execution, and trace rules live in
  [`manufacturing-domain.md`](manufacturing-domain.md), not in this plan.

## Design Decisions

### Generic model and ownership

The generic design is defined once in
[`manufacturing-domain.md`](manufacturing-domain.md); this plan supplies Muar
requirements against that contract.

- Use the generic plan as the authority for Stock, Manufacturing, the one
  ledger, genealogy, opaque context references, configuration ownership, and
  the Domain/Extension rule.
- Validate those contracts against the Muar workflow below; do not restate or
  fork their design here.
- Record a real `MrPackaging` seam only when site evidence shows that the
  public contract and generic configuration cannot express the requirement.

### Capture and rollout

The Muar operation needs a low-friction capture method and evidence before a
full plant rollout.

- **Option A — barcode and handheld scanner:** low cost, printable on site,
  replaceable, and suitable for unit-by-unit roll handling.
- **Option B — RFID:** fewer scans, but unnecessary for unit-by-unit handling,
  adds tag cost, and complicates plant reader placement.
- **Option C — automatic width measurement:** removes one manual number, but
  costs capital before cut planning and yield reporting are proven.
- **Recommendation — Option A first:** use a barcode plus at most one typed
  measured width at roll output; reconsider automatic measurement after the
  cut workflow proves value.
- **Roll identity:** identify every roll, not only the extruder run, because
  cure age and cut yield belong to the individual roll.
- **Rollout order:** start with receiving and weigh tickets, then add runs and
  cure, then lamination/cutting, then packing/despatch and reconciliation.

## Public Contract

Mr Packaging Sdn Bhd consumes the generic contract and adds these customer
requirements.

- Receiving records supplier, vehicle, material identity, location, date,
  actor, declared weight, gross, tare, measured net, and variance.
- Extrusion records blend composition, colour, extruder, run, production
  time, and each roll's measured width, thickness, and length.
- Cure records production time, current location, cure age, configured minimum,
  and any override. Under-cured consumption is refused by default; an override
  needs an explicit Base Authz capability, a mandatory reason, and an immutable
  operational record.
- Lamination and cutting record input rolls, output, demand source, target
  width, actual product, trim/offcut, waste, operator, and yield.
- The demand source is confirmed before matching is built. Mr Packaging Sdn Bhd
  currently runs to a monthly forecast, not an assumed sales-order backlog.
- Packing and despatch record finished-pack identity, quantity, unit,
  destination, shipment identity, and terminal movement.
- Reconciliation reports expected versus actual input, output, trim, waste, and
  stock by operation, execution, supplier, period, order or batch where
  present, resource, and location.
- Provenance separates measured, declared, counted, and derived quantities, and
  shows the conversion-basis version used for normalised mass.
- Resubmission is idempotent, concurrent consumption is protected, late entry
  preserves effective and recorded times, and correction is compensating rather
  than an edit or delete.
- A finished pack traces backward to rolls, runs, and supplier receipts; a
  receipt traces forward to its descendants.

### `MrPackaging` Extension boundary

The Extension is a narrow customer seam, not a second manufacturing model.

- It may own Mr Packaging Sdn Bhd vocabulary or workflow presentation that is
  not a canonical Domain name.
- It may own a confirmed external-system integration or customer-specific
  import/export.
- It may own a calculation, alert, approval, or report that common
  configuration cannot express.
- It must not own the Stock ledger, Lot/Unit Genealogy, generic units of
  measure, Production execution semantics, foam process configuration, route
  templates, cure duration, tolerances, output roles, or later ISO modules.
- The common Domain must remain complete when `MrPackaging` is absent.

### Acceptance

The customer workflow is accepted when a representative Muar month closes with
known evidence.

- A clerk records one lorry and the supplier variance is visible without a
  second ledger.
- An operator labels rolls and resolves them after a physical 7–10 day cure.
- The system refuses an under-cured consumption by default and records an
  authorised override with capability, actor, reason, time, and affected roll.
- A known 1200mm-to-800mm cut reports product, trim, waste, and attributable
  yield.
- A shipped pack traces back to its roll, run, and supplier receipt, and a
  receipt traces forward to its descendants.
- A monthly reconciliation reports unexplained variance and distinguishes
  measured material loss from derived-measurement uncertainty.
- The capture flow uses one scan and at most one manual number at each designed
  point, subject to site validation.
- The result demonstrates operational control and traceability without claiming
  ISO 9001, ISO 14001, ISO 45001, or customer certification.

## Phases

### Phase 1 — Stock ledger and receiving

This phase proves the physical workflow and records the first receipts in the
generic Stock ledger.

- [ ] Confirm where weighing occurs, label survivability, network coverage,
  demand source, and applicable certification requirements.
- [ ] Confirm receiving fields and units with the clerk and supplier process.
- [ ] Mount Inventory/Stock and prove its migration and public posting path.
- [ ] Add receiving and warehouse locations and material units.
- [ ] Record a representative lorry as one balanced receipt with declared and
  measured weight, native measurement, provenance, and normalised mass.
- [ ] Show supplier variance over time and retain known discrepancy examples.

Validation: a Mr Packaging Sdn Bhd clerk completes one lorry in one capture flow,
the receipt posts through Stock, and the resulting variance is attributable.

### Phase 2 — Roll identity and genealogy

This phase makes the generic Stock contract carry roll identity without adding
manufacturing semantics to Stock.

- [ ] Record balanced transforms and genealogy with native measurement,
  provenance, conversion basis, and normalised mass.
- [ ] Create one labelled roll per extrusion output with measured dimensions and
  production date.
- [ ] Run a physical 7–10 day label trial and confirm roll, location, and cure
  age resolution.

Validation: receipts, transforms, ancestry, append-only corrections,
double-consumption protection, and idempotent resubmission pass for Muar data.

### Phase 3 — Production, cure, and conversion

This phase records the actual extrusion and cure workflow through generic
Production configuration.

- [ ] Mount Manufacturing / Production Operations with a Production module
  depending on Inventory/Stock's public contract.
- [ ] Configure three colours, recycled blend, extruders, roll outputs, cure
  duration, and conversion bases as Domain data.
- [ ] Record selected definition, route, operation, execution, inputs, outputs,
  resource, and opaque context references.
- [ ] Configure the Domain's cure hold for Muar rolls and verify that
  under-cured consumption is refused and an authorised override is recorded.
- [ ] Add `MrPackaging` only if site validation identifies behaviour that common
  configuration and public contracts cannot express.

Validation: one roll execution is traceable through Stock genealogy and
Manufacturing trace without duplicated ancestry.

### Phase 4 — Lamination, cutting, packing, and despatch

This phase closes the account for product, trim, waste, and finished packs.

- [ ] Confirm the demand source before cut matching.
- [ ] Configure lamination, cutting, packing, and despatch routes and resources.
- [ ] Record product, trim/offcut, and waste as identified outputs of one
  balanced transaction.
- [ ] Report yield per roll, run, operation, and operator, including the known
  1200mm-to-800mm example.
- [ ] Trace finished packs to despatch and back to supplier receipts.

Validation: the representative cut and shipment close their material account.

### Phase 5 — Reconciliation and acceptance

This phase gives the customer a monthly view that explains every material gap.

- [ ] Report expected versus actual by operation, supplier, period, resource,
  location, order or batch where present, and stock position.
- [ ] Split variance by measured, declared, counted, and derived provenance.
- [ ] Rank unexplained variance and show the affected roll, run, receipt, or
  finished pack.
- [ ] Verify idempotency, concurrent consumption, backdating, reversal, cure
  override, tenant boundaries, and append-only correction behaviour.
- [ ] Record any real `MrPackaging` seam before implementation expands.

Validation: Mr Packaging Sdn Bhd can reconcile a representative month and
identify every unresolved discrepancy as an open investigation.

## Open Assumptions

These assumptions need evidence before later phases become committed.

- Selling and packing units remain unconfirmed for pricing; they do not block
  the ledger's native-observation model.
- Label survivability, weighing locations, network coverage, demand source, and
  certification scope require on-site validation.
- AutoCard is assumed replaced rather than integrated. A required import or
  synchronisation belongs in `MrPackaging` only after a public seam exists.
- A paper or spreadsheet weigh-ticket and cut-yield discipline may bridge the
  rollout and provide known examples before the application workflow is live.
