# Working under apps/domains/

This is the mount root for optional Domains. Read root `AGENTS.md` and the normative [`composition model`](../../docs/architecture/0010_composition-model.md) before changing a Domain. The repository naming and mounting rules below apply to Extensions too; `apps/extensions/AGENTS.md` points here.

## Repository boundary

Each immediate child is one independently sourced Domain repository and installation choice. The Domain owns its `bilimbi.container.exs` and `mix.exs`; its immediate child modules own their descriptors, public APIs, migrations, tests, and documentation. The main Bilimbi repository tracks this guide but ignores mounted Domain repositories.

Use stable logical IDs and declared dependencies. A Domain may depend on Base, Core, and a Domain whose public contract a real business invariant requires. It must not depend on an Extension or reach into another module's private schema or queries. Keep customer-specific integration in an Extension unless a confirmed shared workflow belongs in the Domain.

Domain code uses only meta-terms, such as material, material type, resource, resource type, property, operation, and role. Specific industry, material, product, equipment, or line names are configuration data: never code identifiers, schema constants, or fixed inclusion lists. Anything a company might name differently must be configurable.

## Repository names

An optional Domain repository is named `b-dom-<id>` and an Extension repository `b-ext-<id>`, in whichever GitHub organization owns it. Clone it into a folder named after the container ID, with hyphens turned into underscores, because discovery requires the folder name to equal the snake_case container ID.

```bash
git clone https://github.com/<owner>/b-dom-<id>.git apps/domains/<id_with_underscores>
git clone https://github.com/<owner>/b-ext-<id>.git apps/extensions/<id_with_underscores>
```

`BelimbingApp/b-dom-factory` mounts at `apps/domains/factory`. A customer Extension mounts under `apps/extensions/` from the organization that owns it.

## Mounting

Name the mounted directory after its container `id`, and give the container `mix.exs` that same `app:`. Discovery rejects a mismatched name or a container in the wrong role folder; the rules are in `apps/base/module_registry/docs/README.md`. Run `mix bilimbi.migrate` and the other database tasks from the umbrella root, never from inside the mounted repository: that runtime cannot see the whole graph, so `ModuleRegistry.complete_modules!/0` refuses it.

Unmounting keeps the repository's tables, rows, and ledger rows; `bilimbi_migration_provenance` is what lets `mix bilimbi.migrate` accept them afterwards. Never edit or renumber an applied migration: a remount that ships a different file under an applied version is refused. The provenance rules are `docs/architecture/database.md` "Ledger and execution".

## Maintaining this file

Record only placement mistakes that recur across Domains and Extensions. Put module-specific rules with the owning module, and keep composition rules in the normative architecture document.
