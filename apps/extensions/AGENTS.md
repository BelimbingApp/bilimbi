# Working under apps/extensions/

This is the mount root for optional Extensions. Read root `AGENTS.md` and the normative [`composition model`](../../docs/architecture/0010_composition-model.md) before changing an Extension.

## Repository boundary

Each immediate child is one independently sourced Extension repository and installation choice. The Extension owns its `bilimbi.container.exs` and `mix.exs`; its immediate child modules own their descriptors, public APIs, migrations, tests, and documentation. The main Bilimbi repository tracks this guide but ignores mounted Extension repositories.

An Extension adapts installed capabilities through declared public contracts and supported contributions. It may depend on Base, Core, or installed Domains; another Extension dependency needs a concrete business invariant. It must not read private tables or queries, take ownership of another module's durable records, or make that module fail when the Extension is absent. Repository ownership, visibility, and licensing do not determine whether a capability is an Extension.

## Mounting

Name the mounted directory after its container `id`, and give the container `mix.exs` that same `app:`. Discovery rejects a mismatched name or a container in the wrong role folder; the rules are in `apps/base/module_registry/docs/README.md`. Run `mix bilimbi.migrate` and the other database tasks from the umbrella root, not from inside the Extension: that runtime cannot see the whole graph, so `ModuleRegistry.complete_modules!/0` refuses it.

Unmounting an Extension keeps its tables, rows, and ledger rows; `bilimbi_migration_provenance` is what lets `mix bilimbi.migrate` accept them afterwards (`apps/core/compatibility/lib/compatibility/migration_provenance.ex`). Never edit or renumber an applied migration: a remount that ships a different file under an applied version is refused.

## Maintaining this file

Record only placement mistakes that recur across Extensions. Put customer-specific rules with the owning Extension, and keep composition rules in the normative architecture document.
