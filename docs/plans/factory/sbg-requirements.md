# docs/plans/factory/sbg-requirements.md

**Status:** Proposed customer requirements
**Last Updated:** 2026-09-25
**Sources:**
- [`docs/plans/factory/0000-factory-domain.md`](0000-factory-domain.md)
- [`docs/plans/factory/0010-inventory-module.md`](0010-inventory-module.md)
- [`docs/plans/domain-extension-layer-rollout.md`](../domain-extension-layer-rollout.md)
- SBG `README.md`
- SBG `AGENTS.md`
- SBG `docs/production/glue-production-dashboard.md`
- SBG `docs/ibp/00_master.md`
- SBG `docs/ibp/06_cross-cutting-requirements.md`
- SBG `docs/ibp/13_ax-live-data-delivery.md`
- SBG `docs/ibp/16_inventory-value.md`
- SBG `docs/qac/1-qac-domain-model.md`
- SBG `docs/ax-connector/ax-connector-extraction-plan.md`
- SBG transition capability and access-gap notes
- [Pull request 804](https://github.com/BelimbingApp/bilimbi/pull/804)

**Agents:** codex/gpt-5.6-luna (earlier work),
codex/gpt-6-luna-xhigh (earlier work), codex/gpt-6-sol-medium (Factory boundary revision),
claude/claude-opus-5.5 (no-mistakes review agent)

## Problem Essence

SBG's adhesive-tape operation needs one auditable account across AX facts,
production, planning, inventory value, procurement, and quality work.

- Production, raw-material planning, purchase commitments, month-end value, and
  QAC evidence currently arrive from different systems, workbooks, and manual
  processes.
- A production result must identify its source, freshness, unit, period, and
  owner before it can support a decision.
- Glue batches need reactor, operator, wet/dry output, material usage, lot, and
  quality context; coating and slitting need production-order, line, output,
  and yield context.
- BA and BOPP planning needs explicit material, container, conversion, forecast,
  safety-stock, and procurement assumptions rather than hidden spreadsheet
  formulas.
- AX access and recipe information have different confidentiality and write
  rules; a dashboard must not turn an unverified source into an operational
  fact or expose private recipe data.

## Desired Outcome

The `SbGroup` Extension should give SBG a source-aware adhesive-tape operation while reusing the common Factory contracts. As the second Factory build's validation case, it checks the modules proven with Mr Packaging against glue, coating, slitting, and historical AX production facts.

- One common ledger records SBG's material receipts, consumption, outputs, and
  adjustments; it is not duplicated by AX, IBP, or Inventory Value.
- Glue production, coating, and slitting runs link inputs, outputs, lots,
  resources, quality evidence, and source facts through public contracts.
- IBP explains BA/BOPP demand, container planning, forecasts, safety stock,
  procurement commitments, and conversion assumptions.
- Inventory Value publishes immutable, reviewable month-end revisions with
  quantity, value, unit, adjustment, and provenance evidence.
- A shared Quality capability should own QAC cases, evidence, timelines,
  supplier requests, and corrective actions. Its placement is decided when the
  workflow is built; `SbGroup` supplies SBG policy, AX mapping, integration,
  and presentation through its public contract.
- Every dashboard identifies source, freshness, unit, calculation basis, and
  permissions; no unsupported yield, wastage, energy, labour, or quality value
  is presented as measured fact.

## Top-Level Components

These components describe what SBG needs and where the behaviour belongs.

- **Factory Inventory** — owns the common items, locations, units of measure,
  material units, append-only Material Transaction ledger, and Lot/Unit
  Genealogy. It remains usable without `SbGroup`.
- **AX Connector** — `SbGroup` owns the single AX boundary: typed source facts,
  schema checks, source snapshots, candidate and active batches, provenance,
  freshness, and tenant/company mapping. It submits production history to
  Factory Production Execution's import contract; it does not post production
  effects directly to Inventory or issue raw SQL writes to AX application tables.
  Any future AX write uses an approved AIF or staging path.
- **Production** — glue batches, reactors, operators, helpers, wet/dry output,
  material usage and lots, coating, and slitting are process families
  configured in Factory's Product Definition module. Production Execution's import
  contract validates production commands and historical facts, then commits
  execution and Inventory effects atomically. `SbGroup` maps AX facts into that
  contract; its dashboards can expose monthly, yearly, reactor, glue, and
  coating-line views.
- **IBP** — `SbGroup` owns BA/BOPP planning, forecasts, weekly planning,
  safety-stock alerts, container planning, pricing and cost sensitivities, and
  the evidence linking planning values to AX facts.
- **Procurement** — `SbGroup` owns AX open-PO commitments, supplier, item,
  UOM, price, currency, quantity, ETA/ETD, Port Klang, invoice/K1, and monthly
  rollups.
- **Inventory Value** — `SbGroup` owns month-end physical and financial
  quantity/value reports, immutable revisions, published/reviewed status,
  adjustments, and provenance. It does not replace Inventory's operational ledger.
- **Quality capability (future)** — owns the shared QAC case, evidence, supplier-request, review, and corrective-action model. Its placement as a Factory module or separate Domain waits for the confirmed workflow, including the Supplier Quality overlap.
- **`SbGroup` Extension boundary** — contains SBG's AX mapping and integration,
  planning, procurement, inventory-value needs, SBG policy, and presentation.
  For Quality, it supplies only SBG policy, AX mapping and integration, and
  presentation through Quality's public contract; it owns no
  QAC case, evidence, or corrective-action model. It does not reach into
  private Domain tables or queries.

## Design Decisions

The design keeps common material and production truth reusable while placing
SBG's source systems and workflows at the customer boundary.

### AX source boundary

AX facts must be typed, attributable, and freshness-aware before other SBG
capabilities consume them.

- **Option A — query AX directly from each feature:** short local paths, but
  duplicated credentials, inconsistent source rules, and unsafe coupling.
- **Option B — copy AX tables into the generic Domain:** simplifies reads, but
  leaks SBG and AX vocabulary into a reusable contract.
- **Option C — use one `SbGroup` AX Connector:** centralises extraction,
  validation, snapshots, source batches, freshness, and mapping while exposing
  approved facts to SBG features.
- **Recommendation — Option C:** the Connector is the only AX boundary. Keep
  it read-only for the initial scope; use an approved AX AIF or staging path if
  a future write is authorised, never raw SQL to AX application tables.

### Production facts and operator capture

The first SBG production views must distinguish source facts from operator
evidence and must not invent missing measurements.

- **Option A — treat current workbooks as the system of record:** familiar,
  but weakly versioned and difficult to audit or refresh safely.
- **Option B — treat AX extracts as complete truth:** consistent for available
  fields, but hides gaps such as wastage reason, energy, labour, and GSM data.
- **Option C — retain typed AX/workbook source facts with readiness indicators,
  then add approved operator capture:** honest about gaps and allows production
  workflows to mature without fabricated values.
- **Recommendation — Option C:** preserve source, timestamp, freshness, and
  readiness fields such as type, revision, previous batch, and cleaning
  sequence; add operator capture only for a validated public seam.

### Units, conversions, and planning assumptions

Planning and cost calculations must expose the unit and basis used for every
conversion.

- **Option A — keep the existing workbook formulas implicit:** quick to copy,
  but impossible to audit or safely revise.
- **Option B — put every conversion in Inventory:** gives one location, but mixes
  item-level UOM facts with customer-specific container planning and cost
  assumptions.
- **Option C — keep item/UOM conversions in Factory Inventory and SBG planning bases in `SbGroup` configuration:** preserves common quantity semantics and makes each planning assumption visible.
- **Recommendation — Option C:** represent BA/BOPP quantities in MT, container
  planning in JR, and costs in their stated bases. The current planning facts
  include 1 JR = 9.5 MT BOPP, 1 JR = 7.56 MT BA, and coating sensitivity in
  USD/190 kg; these remain reviewed, versioned configuration rather than
  hidden constants.

## Public Contract

The SBG contract must make every operational number explainable without exposing
private AX or recipe implementation details.

- Warehouse receipts and ordinary warehouse movements post directly through Factory Inventory's Material Transaction contract. Production commands and AX history imports pass through Production Execution's import contract; `SbGroup` cannot post production effects directly to Inventory, which accepts production context only from its registered Production Execution authority.
- Production Execution commits execution completion, Inventory effects, and any required override evidence together, or commits none of them. A failed or retried import cannot leave a partial production record or duplicate material effect.
- AX facts expose source identity, extraction time, effective period, freshness,
  schema/version checks, candidate or active status, tenant/company mapping,
  and the approved fact type.
- Glue production records batch/job number, production date/month, reactor,
  glue item/type, capacity, revision, wet and dry quantities, operator/helper,
  previous batch, cleaning sequence, material usage, material lot, and
  references to Quality results where available.
- Coating and slitting records production-order and coating-line facts, input
  consumption, good output, and yield basis. A known transition report may
  compare 422,089 coating consumption lines in 2026 with good output, but the
  system must identify the source and period rather than infer wastage reasons.
- IBP records BA/BOPP demand and supply in MT, container plans in JR, forecasts,
  safety stock, weekly planning, purchase commitments, formulas, and the
  configuration version behind each result.
- Procurement records open PO lines, supplier, item, UOM, price, currency,
  quantity, ETA/ETD, Port Klang, invoice/K1, and monthly rollups from the
  approved source.
- Inventory Value records a month-end revision with physical and financial
  quantity/value, UOM, adjustments, provenance, reviewer, publication status,
  and immutable prior versions. A failed refresh cannot replace a complete
  published version.
- The chosen Quality owner records QAC case type, policy state, evidence, timeline,
  supplier or
  customer request, corrective action, reviewer, and any AI assistance as
  attributable, reviewable, and reversible support. `SbGroup` adds SBG policy,
  AX mapping/integration, and presentation through the Quality API; it does
  not own this record model.
- Every result identifies source, freshness, unit, owner, formula or conversion
  basis, and access policy. Missing energy, labour, GSM, wastage-reason, or
  discontinued COA data remains explicitly unavailable.
- `SbGroup` can be absent without changing the generic ledger, genealogy, or
  Factory Production Execution contract.

## Phases

### Phase 1 — Inventory ledger and AX fact foundation

This first slice gives SBG a common material account and a trustworthy source
boundary before planning or dashboards depend on it.

- **SBG receives:** BA, BOPP, glue, coating, and other mapped material facts
  with native UOM, location, lot, source, freshness, and provenance.
- [ ] Mount Factory and prove Inventory receiving, balanced posting, idempotent
  retry, concurrent-consumption protection, reversal, and receipt lot identity
  through its public contract.
- [ ] Mount the `SbGroup` AX Connector with schema checks, candidate/active
  source batches, provenance, freshness, and tenant/company mapping.
- [ ] Confirm which AX production, item, inventory, purchase-order, and value
  facts are available for the first source slice.
- [ ] Keep all AX writes and raw AX SQL out of Factory; AX production history waits for Phase 2's execution/import contract.

Validation: an SBG material receipt and its AX source evidence reconcile by
quantity, UOM, lot, period, source, and freshness without a second ledger.

### Phase 2 — Production runs and material genealogy

This phase connects SBG's glue, coating, and slitting work to Factory's Production Execution contract.

- **SBG receives:** traceable glue batches and coating/slitting runs with
  material usage, lots, operators/resources, output, and source readiness.
- [ ] Configure glue batch, reactor, wet/dry output, material usage, Quality
  result references, previous batch, cleaning sequence, and production
  date/month as Domain data; `SbGroup` supplies only the AX source mapping.
- [ ] Submit live production facts and historical AX actuals through
  Production Execution's import contract so validation, Inventory effects, and
  any required override evidence commit together.
- [ ] Link coating and slitting production-order facts, line, consumption,
  good output, and yield to Inventory transactions and Production Execution trace.
- [ ] Mark unavailable wastage reasons, energy, labour hours, GSM, and stopped
  COA fields as gaps; never fill them with inferred values.
- [ ] Keep recipe details restricted and ensure external AI receives only
  approved redacted or synthetic information.

Validation: one glue batch and one coating/slitting period trace from source
fact to material usage and output through the same Inventory genealogy contract.

### Phase 3 — IBP and procurement evidence

This phase turns source-backed material positions into reviewable planning and
supply decisions.

- **SBG receives:** BA/BOPP forecasts, safety-stock views, JR planning,
  purchase commitments, and weekly planning with explicit formulas and dates.
- [ ] Implement BA/BOPP planning in MT and expose the JR conversions and
  versioned planning assumptions.
- [ ] Connect approved production consumption by AX item and date to IBP
  without treating inventory movement alone as a production fact.
- [ ] Load open PO commitments with supplier, UOM, price/currency, quantity,
  ETA/ETD, Port Klang, invoice/K1, and monthly rollup fields.
- [ ] Replace old workbook intake only after AX source readiness and
  reconciliation are proven; retain provenance for any transition period.

Validation: a reviewed weekly plan explains each demand, stock, conversion,
and open-PO value back to its source and freshness.

### Phase 4 — Inventory Value and Quality integration

This phase closes the month-end value loop and connects SBG to the future
Quality capability without changing the operational ledger or duplicating its
case model. QAC and supplier requests wait for the Quality placement decision.

- **SBG receives:** immutable published/reviewed inventory-value revisions and
  QAC case workflows owned by the chosen Quality capability, with SBG-specific
  policy and presentation through its public contract.
- [ ] Produce month-end physical and financial quantity/value snapshots with
  UOM, adjustments, reviewer, publication state, and provenance.
- [ ] Refuse replacement of a complete published revision when a refresh fails;
  create a new candidate or revision instead.
- [ ] Decide Quality's placement and Supplier Quality overlap before building
  QAC and supplier-request integration.
- [ ] Integrate QAC evidence timelines, supplier requests, corrective actions,
  review gates, and attributable/reversible AI assistance
  through its public API; keep SBG-specific policy and presentation in
  `SbGroup`.
- [ ] Connect relevant production, procurement, and source facts by public
  references rather than private table reads.

Validation: one month-end revision and one QAC case can be reviewed from
published output to its source evidence and responsible owner, with the case
model owned by Quality rather than `SbGroup`.

### Phase 5 — Dashboards, controls, and approved integrations

This phase makes the SBG operation useful at scale while preserving source and
confidentiality boundaries.

- **SBG receives:** production, IBP, procurement, inventory-value, AX health, and QAC views from the chosen Quality capability, with explicit permissions and freshness indicators.
- [ ] Add monthly/yearly/reactor/glue and coating-line views only over validated
  facts and clearly label unavailable fields.
- [ ] Add source-health, candidate/active batch, freshness, schema, and
  reconciliation monitoring for the AX Connector.
- [ ] Prove recipe, lot, supplier, customer, and Quality QAC access
  policies with reviewable audit evidence; `SbGroup` owns only its policy,
  integration, and presentation through the approved seam.
- [ ] Use an approved AX AIF or staging contract for any future write; do not
  add direct raw SQL writes to AX application tables.
- [ ] Record the public seam before adding any `SbGroup` behaviour that the
  generic Domain and configuration cannot express.

Validation: SBG users can make a planning, production, procurement, value, or
quality decision and identify source, freshness, unit, owner, and access basis.

## Open Assumptions

These assumptions need source and owner confirmation before implementation is
committed.

- AX read access, source schemas, production-order availability, and current
  extract cadence must be confirmed for the first deployment.
- The stated BA/BOPP conversions, planning defaults, cost sensitivities, and
  safety-stock rules require business-owner approval and versioned configuration.
- Transition notes identify gaps in wastage reason, energy, labour, GSM, and
  current COA data; those gaps must remain visible until a source exists.
- SBG must confirm which production, planning, procurement, inventory-value,
  and Quality/QAC roles may view or change each evidence class; Quality owns
  the common case permissions and evidence model.
- No recipe, supplier, customer, or AX fact is assumed public merely because it
  is present in an internal dashboard or workbook.
