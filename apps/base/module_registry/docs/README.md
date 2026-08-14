# Base Module Registry

`apps/base/module_registry/` owns both sides of module composition. Its
`mix/module_discovery.exs` helper discovers and validates source packages while
Mix resolves dependencies. `mix/compile_bilimbi_graph.exs` fingerprints the
installed descriptor graph and refreshes each module package's generated
application resource when composition changes. Mix records each descriptor,
its resolved order, and that fingerprint in OTP application metadata. The
compiled runtime registry consumes that approved order without reimplementing
the dependency graph or depending on source-checkout paths.

An immediate child directory with a valid `bilimbi.module.exs` is an installed
module. The Mix-time registry validates the complete installed graph before
returning deterministically ordered local path dependencies. Runtime validates
that every package was compiled from the same graph and that the generated
positions are complete and dependency-safe before exposing module and
migration contributions.

A non-null migration path has a mandatory `migration_dispositions` map whose
positive version keys exactly equal the migration filenames and whose values
are only `:compatible_baseline` or `:bilimbi_only`. Nil paths omit the field.
Mix-time and runtime validation both fail closed on missing, extra, malformed,
or duplicate versions. Descriptor and migration-file contents participate in
the workspace fingerprint.

Source composition and runtime visibility stay separate. A coordinator such as
Core Compatibility can enumerate only OTP applications in its Mix dependency
closure. Workspace-boundary tests therefore fail when a source-discovered
module that declares `migrations` or a `schema_contract` is absent from
`core/compatibility`'s declared dependencies — the defect class that shipped
Core User inert with green CI.
