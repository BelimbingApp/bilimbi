# Working under apps/domains/

This is the planned mount root for optional Domains. Read root `AGENTS.md` and the normative [`composition model`](../../docs/architecture/0010_composition-model.md) before changing a Domain. The nested Mix discovery mechanism is still subject to the [composition proof](../../docs/plans/domain-extension-layer-rollout.md); a directory mounted here is not yet a working installation.

## Repository boundary

Each immediate child, such as `factory/`, is one independently sourced Domain repository and installation choice. The Domain owns its `bilimbi.container.exs` and `mix.exs`; its immediate child modules own their descriptors, public APIs, migrations, tests, and documentation. The main Bilimbi repository tracks this guide but ignores mounted Domain repositories.

Use stable logical IDs and declared dependencies. A Domain may depend on Base, Core, and a Domain whose public contract a real business invariant requires. It must not depend on an Extension or reach into another module's private schema or queries. Keep customer-specific integration in an Extension unless a confirmed shared workflow belongs in the Domain.

The first planned Domain is [Factory](../../docs/plans/factory/0000-factory-domain.md), with Inventory, Product Definition, and Production Execution as its initial modules. Its first build is validated against Mr Packaging; SBG validates the second build.

## Maintaining this file

Record only placement mistakes that recur across Domains. Put module-specific rules with the owning module, and keep composition rules in the normative architecture document.
