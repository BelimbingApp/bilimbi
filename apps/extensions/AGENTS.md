# Working under apps/extensions/

This is the mount root for optional Extensions. Read root `AGENTS.md` and the normative [`composition model`](../../docs/architecture/0010_composition-model.md) before changing an Extension.

## Repository boundary

Each immediate child is one independently sourced Extension repository and installation choice. The Extension owns its `bilimbi.container.exs` and `mix.exs`; its immediate child modules own their descriptors, public APIs, migrations, tests, and documentation. The main Bilimbi repository tracks this guide but ignores mounted Extension repositories.

An Extension adapts installed capabilities through declared public contracts and supported contributions. It may depend on Base, Core, or installed Domains; another Extension dependency needs a concrete business invariant. It must not read private tables or queries, take ownership of another module's durable records, or make that module fail when the Extension is absent. Repository ownership, visibility, and licensing do not determine whether a capability is an Extension.

## Maintaining this file

Record only placement mistakes that recur across Extensions. Put customer-specific rules with the owning Extension, and keep composition rules in the normative architecture document.
