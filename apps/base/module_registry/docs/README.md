# Base Module Registry

`apps/base/module_registry/` owns both sides of module composition. Its
`mix/module_discovery.exs` helper discovers and validates source packages while
Mix resolves dependencies. It records each descriptor and its resolved order
in OTP application metadata. The compiled runtime registry consumes that
approved order without reimplementing the dependency graph or depending on
source-checkout paths.

An immediate child directory with a valid `bilimbi.module.exs` is an installed
module. The Mix-time registry validates the complete installed graph before
returning deterministically ordered local path dependencies. Runtime validates
that the generated positions are complete and dependency-safe before exposing
module and migration contributions.
