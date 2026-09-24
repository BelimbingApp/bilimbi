# docs/plans/commerce-material-flow-ledger.md

**Status:** Proposed customer requirements
**Last Updated:** 2026-09-25
**Sources:** Client meeting notes, Mr Packaging Sdn Bhd, Muar LDPE foam
plant (2026-08-15); `docs/plans/manufacturing-domain.md`;
`docs/plans/domain-extension-layer-rollout.md`;
`docs/architecture/0010_composition-model.md`; `docs/PORTING_STAGES.md`
(S5); `AGENTS.md` §4, §5, §6; Belimbing
`app/Domains/Commerce/Inventory` (item master, 3 models); material-flow scout
report (2026-09-25)
**Agents:** claude/claude-opus-5, amp/medium-sol, codex/gpt-5

## Problem Essence

Mr Packaging Sdn Bhd in Muar currently relies on manual records for its LDPE
foam material flow. The records do not consistently connect supplier receipts,
extrusion output, cure ageing, lamination, cutting, packing, and despatch, so
short-weighting, loss, theft, and cutting waste cannot be distinguished by
measured evidence.

## Desired Outcome

Mr Packaging Sdn Bhd can record each material step with a practical capture
flow, preserve the observed quantity and its provenance, and reconcile input,
output, trim, waste, and stock by supplier, run, operation, location, and
period. A roll remains identifiable through 7–10 days of cure and through
lamination, cutting, packing, and despatch. The acceptance evidence describes
what the customer can operate and verify; it does not claim that this plan
alone satisfies ISO certification.

## Top-Level Components

- **Customer workflow** — receiving, weighing, extrusion, curing, lamination,
  cutting to width, packing, and shipping for Mr Packaging Sdn Bhd's Muar
  operation.
- **Material observations** — supplier, vehicle, gross/tare/net, declared and
  measured weight, roll width/thickness/length, blend composition, cure dates,
  cut outputs, trim, waste, finished packs, and despatch facts.
- **Operational identity** — a durable label for each roll, not only for an
  extruder run, so the label survives cure and supports yield and cure-age
  decisions.
- **Reconciliation and traceability** — supplier variance, per-run and
  per-operation yield, input versus output, trim and waste accounting, stock
  position, and forward/backward ancestry.
- **Capture surface** — printable barcode labels and handheld scanning with no
  more than one manual measurement at a capture point where the process allows
  it.
- **MrPackaging Extension** — the named customer Extension for behaviour that
  cannot be expressed by the generic Domain contracts and configuration. It
  must not own the generic ledger, genealogy, process-family configuration, or
  common execution semantics.
- **Generic Domain boundary** — Inventory/Stock and Manufacturing / Production
  Operations responsibilities, the one ledger, opaque context references,
  definitions versus execution, trace, naming, and later capability modules
  are defined in [`docs/plans/manufacturing-domain.md`](manufacturing-domain.md).
  This plan records only what Mr Packaging Sdn Bhd requires from that Domain.

## Design Decisions

### Generic model and ownership

The generic Inventory/Stock and Manufacturing / Production Operations design is
specified once in [`docs/plans/manufacturing-domain.md`](manufacturing-domain.md).
That plan is the authority for the one append-only Material Transaction ledger,
Lot/Unit Genealogy, units of measure, optional opaque execution/order/batch and
Work Centre/Resource references, Product Definition and process definitions,
execution, Manufacturing trace views, configuration ownership, the two-layer
Domain/Extension rule, canonical names, optional UI labels, and later ISO-driven
capabilities. This customer plan does not create a second generic design or a
second ledger.

Mr Packaging Sdn Bhd requires that common contract to express its foam process
through configuration first. Its process families, route steps, tolerances,
output roles, cure duration, and process-specific conversion bases belong to
the Manufacturing / Production Operations Domain as data. `MrPackaging` is
reserved for a proven customer-specific adaptation that consumes a public
contract, such as customer vocabulary mapping, an external integration, or a
workflow/calculation unavailable through common configuration.

### Capture mechanism

**Option A — barcode labels and handheld scanners.** Labels are printable and
replaceable on site, and operators already handle rolls and packs one at a
time. The method supports a durable roll identity with low capital cost.

**Option B — RFID.** Bulk or no-line-of-sight reads could reduce scans, but
Mr Packaging Sdn Bhd's material is handled unit by unit, tag cost is material,
and the plant environment complicates reader placement.

**Option C — automatic width measurement at extrusion.** This removes one
manual measurement, but it is a capital purchase that solves a smaller problem
than cut planning and yield accounting.

**Recommended: A, with C deferred.** Mr Packaging Sdn Bhd should start with
barcode labels and a typed measured width at roll output. Automatic width
measurement can be reconsidered after the cut-planning and reconciliation
workflow demonstrates value.

### Roll identity and rollout scope

**Option A — identify only the extruder run.** This is quick, but it cannot
show the yield of an individual roll or enforce cure age after rolls diverge.

**Option B — identify every roll and build the whole plant at once.** Per-roll
identity is operationally correct, but a big-bang rollout delays evidence and
asks a labour-constrained operation to change every record at once.

**Option C — identify every roll and release receiving first, then extend by
process.** This preserves the trace needed for cure and cutting while allowing
Mr Packaging Sdn Bhd to prove the lowest-dependency workflow before adopting
the next one.

**Recommended: C.** Roll-level identity is required from extrusion onward;
phased delivery begins with receiving and supplier variance, then adds
extrusion/cure, lamination/cutting, packing/despatch, and reconciliation.

## Public Contract

### Requirements on the generic Domain

Mr Packaging Sdn Bhd's implementation must consume the contracts in
[`docs/plans/manufacturing-domain.md`](manufacturing-domain.md). In particular,
the generic Domain must provide:

- one balanced, append-only Material Transaction ledger owned by
  Inventory/Stock, with filtered views rather than station-specific ledgers;
- Lot/Unit Genealogy owned by Inventory/Stock and queryable backward from a
  shipped pack to supplier receipts and forward from a receipt to everything
  it became;
- native observed quantities and units, provenance (`measured`, `declared`,
  `counted`, or `derived`), versioned conversion bases, and a normalised mass
  equivalent for reconciliation;
- optional opaque references from Stock postings to an operation execution,
  order or batch, and Work Centre/Resource, without Stock learning
  manufacturing semantics;
- separate Product Definition, Formula/BOM, Routing, Operation, Work
  Centre/Resource, and Operation Execution concepts, with Manufacturing trace
  reading Stock genealogy rather than storing it again;
- configuration for foam process families, route steps, tolerances, output
  roles, cure duration, and process-specific conversion bases;
- the idempotency, concurrent-consumption, backdating, reversal, and variance
  behaviour required by the generic public contract.

### Mr Packaging Sdn Bhd workflow requirements

The Muar workflow must support the following observable facts:

- **Receiving:** supplier, lorry or vehicle, gross weight, tare weight, net
  weight, declared weight, measured weight, material identity, date, location,
  actor, and the variance between declared and measured weight.
- **Blend and extrusion:** virgin resin and roughly 30% recycled material,
  three fixed foam colours, extruder identity, production run, production
  date/time, recipe or blend composition, and each roll's measured width,
  thickness, and length.
- **Cure:** a roll's production time, current location, cure age, configured
  minimum cure duration, and any authorised under-cure override with actor,
  reason, time, and affected roll.
- **Lamination and cutting:** input rolls, lamination output, demand source,
  target width, actual cut outputs, trim/offcut, waste, operator, and the
  attributable yield of each roll and run. The system must not assume that
  outstanding sales orders are the demand source: Mr Packaging Sdn Bhd
  currently runs to a monthly forecast.
- **Packing and shipping:** finished pack identity, quantity and unit,
  destination or shipment identity, terminal despatch transaction, and the
  trace from shipped pack back through rolls, runs, and supplier receipts.
- **Reconciliation:** expected versus actual input and output by operation,
  execution, supplier, period, order or batch where present, resource, and
  location; variance split by provenance so derived quantities are not
  confused with measured material loss.

### MrPackaging Extension boundary

`MrPackaging` is the customer Extension name. It may own customer-specific
behaviour that consumes a documented public Domain contract, including:

- Mr Packaging Sdn Bhd vocabulary or workflow presentation that is not a
  generic canonical name;
- a confirmed external-system integration or customer-specific import/export;
- a customer-specific calculation, alert, approval, or report that cannot be
  expressed as Manufacturing configuration and common execution logic.

`MrPackaging` must not own or duplicate Inventory/Stock's Material Transaction
ledger or Lot/Unit Genealogy, Manufacturing's common execution semantics,
generic units of measure, foam process-family configuration, route templates,
tolerances, cure duration, output roles, or ISO capability modules. The Domain
must remain complete when `MrPackaging` is absent. The Extension is not a
placeholder for ordinary Mr Packaging Sdn Bhd configuration.

### Acceptance

Mr Packaging Sdn Bhd's requirements are accepted when a representative Muar
workflow can demonstrate all of the following:

- a receiving clerk records one lorry with declared and measured weight and the
  supplier variance is visible without a second ledger;
- an extrusion operator creates individually labelled rolls with measured
  dimensions and the labels resolve after a 7–10 day cure;
- the system shows cure age and refuses under-cured consumption by default,
  while an authorised override records its reason and actor;
- a cut from a known roll records product, trim, and waste as explicit outputs,
  and reports the roll's attributable yield;
- a finished pack can be traced backward to the relevant roll, run, and
  supplier receipt, while a receipt can be traced forward to its descendants;
- a monthly reconciliation separates measured, declared, counted, and derived
  quantities and reports unexplained variance by operation;
- resubmitting a capture does not double-post, concurrent consumption cannot
  consume the same quantity twice, and corrections are compensating
  transactions rather than edits or deletes;
- the workflow is usable with one scan and at most one manual number at each
  designed capture point, subject to site validation.

These acceptance statements demonstrate operational control and traceability;
they do not certify Mr Packaging Sdn Bhd against ISO 9001, ISO 14001, ISO
45001, or any customer standard.

## Phases

### Phase 1 — Site validation and receiving

Goal: confirm the physical workflow and deliver the first useful evidence for
Mr Packaging Sdn Bhd.

- [ ] Confirm where weighing occurs, how labels survive the cure environment,
  network coverage at each capture point, the real demand source, and the
  applicable customer or certification requirements.
- [ ] Confirm supplier, vehicle, material, location, actor, declared weight,
  gross, tare, and measured net fields with the receiving clerk.
- [ ] Record a representative lorry through one receiving workflow and show
  supplier declared-versus-measured variance over time.
- [ ] Establish the operational acceptance evidence and retain known
  discrepancy examples for later reconciliation.

Validation: a Mr Packaging Sdn Bhd receiving clerk completes a representative
lorry in one screen or capture flow, and the resulting variance is attributable.

### Phase 2 — Stock ledger and roll identity

Goal: make the generic Stock contract useful for Mr Packaging Sdn Bhd without
adding manufacturing semantics to Stock.

- [ ] Mount Inventory/Stock through the composition model and prove its
  migration and public posting path end to end.
- [ ] Add receiving and warehouse locations, material units, and bidirectional
  Lot/Unit Genealogy through Stock's public API.
- [ ] Add balanced receipts and transforms with native measurements,
  provenance, conversion basis, and normalised mass as required by the generic
  plan.
- [ ] Create individually labelled roll units at extrusion output with
  measured width, thickness, length, and production date.
- [ ] Confirm labels resolve to roll, location, and cure age after a physical
  7–10 day trial.

Validation: known receipts, transforms, ancestry, append-only behaviour,
double-consumption protection, and idempotent resubmission pass for the Muar
workflow.

### Phase 3 — Production, cure, and conversion

Goal: record the actual extrusion and cure workflow through the generic
Production module and configuration.

- [ ] Mount Manufacturing / Production Operations with its first Production
  module and declared dependency on Inventory/Stock.
- [ ] Configure Mr Packaging Sdn Bhd's three colours, roughly 30% recycled
  blend, extruder resources, roll outputs, cure duration, and conversion bases
  as Domain data.
- [ ] Record the selected product/process definition, route, operation,
  execution, inputs, outputs, resource, and opaque context references through
  the generic contracts.
- [ ] Refuse under-cured consumption by default and record an authorised
  override as an immutable nonconformance with mandatory reason.
- [ ] Add `MrPackaging` only if site validation identifies behaviour that
  configuration and public Domain contracts cannot express.

Validation: a roll execution can be traced through Stock genealogy and
Manufacturing trace views without a duplicated ancestry record.

### Phase 4 — Lamination, cutting, packing, and despatch

Goal: account for every roll's useful product, trim, waste, and finished pack.

- [ ] Confirm whether the demand source is monthly forecast lines, manual
  cutting batches, finished-goods replenishment, or another recorded source.
- [ ] Configure lamination, cutting-to-width, packing, and despatch routes
  with their operations, resources, tolerances, and output roles.
- [ ] Record cut product, trim/offcut, and waste as explicit identified outputs
  of one balanced transaction.
- [ ] Report yield per roll, run, operation, and operator, including a known
  1200mm-to-800mm example as an attributable number.
- [ ] Trace finished packs to despatch and back through rolls, executions, and
  supplier receipts.

Validation: the representative cut and shipment close their material account,
including explicit trim/waste and a forward/backward trace.

### Phase 5 — Reconciliation and operational acceptance

Goal: give Mr Packaging Sdn Bhd a monthly view that distinguishes measurement
uncertainty from material variance.

- [ ] Report expected versus actual input, output, trim, waste, and stock by
  operation, execution, supplier, period, order or batch where present,
  resource, and location.
- [ ] Split variance by measured, declared, counted, and derived provenance,
  preserving the conversion basis version used.
- [ ] Rank unexplained variance and show the affected roll, run, receipt, or
  finished pack.
- [ ] Verify idempotency, concurrent consumption, backdating, reversal, cure
  override, tenant boundaries, and append-only correction behaviour against
  representative Muar records.
- [ ] Record the accepted customer workflow, unresolved site assumptions, and
  any real `MrPackaging` Extension seam in this plan before implementation
  proceeds to the next slice.

Validation: Mr Packaging Sdn Bhd can reconcile a representative month and
explain every material discrepancy or identify it as an open investigation.

## Open Assumptions

- Selling and packing units remain unconfirmed for pricing purposes; they do
  not block the ledger because native observations and normalised mass are
  recorded separately.
- Label survivability, exact weighing locations, network coverage, demand
  source, and certification scope require on-site validation before Phases 3–5
  are treated as committed acceptance criteria.
- The plant runs to a monthly forecast rather than to an assumed sales-order
  backlog. The demand source must be identified before matching or cut planning
  is implemented.
- AutoCard is assumed to be replaced rather than integrated. If Mr Packaging
  Sdn Bhd requires an import or synchronisation, that requirement belongs in
  `MrPackaging` only after a public-contract seam is identified.
- A paper or spreadsheet weigh-ticket and cut-yield discipline may be used
  during rollout to produce known examples and preserve operations before the
  application workflow is available.
