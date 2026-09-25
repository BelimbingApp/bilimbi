# Working under apps/domains/

This is the mount root for optional Domains. Read root `AGENTS.md` and the normative [`composition model`](../../docs/architecture/0010_composition-model.md) before changing a Domain.

## Repository boundary

Each immediate child is one independently sourced Domain repository and installation choice. The Domain owns its `bilimbi.container.exs` and `mix.exs`; its immediate child modules own their descriptors, public APIs, migrations, tests, and documentation. The main Bilimbi repository tracks this guide but ignores mounted Domain repositories.

Use stable logical IDs and declared dependencies. A Domain may depend on Base, Core, and a Domain whose public contract a real business invariant requires. It must not depend on an Extension or reach into another module's private schema or queries. Keep customer-specific integration in an Extension unless a confirmed shared workflow belongs in the Domain.

## Maintaining this file

Record only placement mistakes that recur across Domains. Put module-specific rules with the owning module, and keep composition rules in the normative architecture document.
