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
