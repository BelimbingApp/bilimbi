# Working under apps/extensions/

This is the planned mount root for optional Extensions. Read root `AGENTS.md` and the normative [`composition model`](../../docs/architecture/0010_composition-model.md) before changing an Extension. The nested Mix discovery mechanism is still subject to the [composition proof](../../docs/plans/domain-extension-layer-rollout.md); a directory mounted here is not yet a working installation.

## Repository boundary

Each immediate child, such as `sb_group/`, is one independently sourced Extension repository and installation choice. The Extension owns its `bilimbi.container.exs` and `mix.exs`; its immediate child modules own their descriptors, public APIs, migrations, tests, and documentation. The main Bilimbi repository tracks this guide but ignores mounted Extension repositories.

An Extension adapts installed capabilities through declared public contracts and supported contributions. It may depend on Base, Core, Domains, or another Extension when a concrete invariant requires that public contract. It must not read private tables or queries, take ownership of a Domain's ledger, or make a Domain fail when the Extension is absent. Repository ownership, visibility, and licensing do not determine whether a capability is an Extension.

The [SBG requirements](../../docs/plans/factory/sbg-requirements.md) place AX source mapping in the planned `SbGroup` Extension and reusable material and production work in Factory. Mr Packaging's current requirements need Factory configuration; add a `MrPackaging` Extension only for a confirmed gap in its public contracts.

## Maintaining this file

Record only placement mistakes that recur across Extensions. Put customer-specific rules with the owning Extension, and keep composition rules in the normative architecture document.
