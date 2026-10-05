# Base Module Registry

Module descriptors are the machine-readable authority for installed database
contributors. Their database meaning and relationship to migrations, schema
contracts, and ledgers are defined in
[Bilimbi Database Architecture](../../../../docs/architecture/database.md).

`apps/base/module_registry/` owns both sides of module composition. Its
`mix/module_discovery.exs` helper discovers and validates source packages while
Mix resolves dependencies. `mix/compile_bilimbi_graph.exs` fingerprints the
installed descriptor graph and refreshes each module package's generated
application resource when composition changes. Mix records each descriptor,
its resolved order, and that fingerprint in OTP application metadata. The
compiled runtime registry consumes that approved order without reimplementing
the dependency graph or depending on source-checkout paths.
A module's `mix.exs` calls `MixDiscovery.module_project/2` and
`module_application/2` and passes only what is its own: the OTP app, the
library `deps` it calls, its aliases, and any `mod:`, `extra_applications:`, or
extra application `env:`. The shared project shape (workspace `_build`, config,
deps and lockfile, the graph compiler, `elixirc_paths`) lives in the helper, so
a shape change is one edit, never one per module.
The host uses the same graph marker to refresh its OTP dependency list even
when a mounted container adds no routes. Unmounting must not leave that
container in the host's generated `.app` file.

Development reload checks reuse parsed literal descriptors and route data in the
calling Mix process, keyed by the full file contents. Executable source is evaluated
on every call. Directory discovery, migration checks, and graph validation still
run each time; same-size edits, restored timestamps, and newly mounted modules
cannot hide behind the parse cache. Application metadata fingerprints reuse the
graph just validated for that metadata rather than discovering it a second time.
Fingerprints read module and route files at their validated descriptor paths,
including nonstandard route filenames, without repeating module-tree scans.

An immediate child directory with a valid `bilimbi.module.exs` is an installed
module. The Mix-time registry validates the complete installed graph before
returning deterministically ordered local path dependencies. Runtime validates
that every package was compiled from the same graph and that the generated
positions are complete and dependency-safe before exposing module and
migration contributions.

In the test environment, all discovered local path dependencies explicitly use
`:test`, including mounted containers and their module dependencies. They share
`_build/test` with package-local test runs, so compiling a host or a dependent
package retains the same test support instead of deleting and rebuilding it.
Other environments retain Mix's default production dependency environment;
production builds exclude test support. Third-party dependencies are unchanged.
Test helpers load support from declared dependencies with `Code.ensure_loaded!/1`
instead of recompiling the same `.ex` files with `Code.require_file/1`.

A non-null migration path has a mandatory `migration_dispositions` map whose
positive version keys exactly equal the migration filenames and whose values
are only `:compatible_baseline` or `:bilimbi_only`. Nil paths omit the field.
Mix-time and runtime validation both fail closed on missing, extra, malformed,
or duplicate versions. Descriptor and migration-file contents participate in
the workspace fingerprint.

Base and Core containers are direct children of `apps/`. Optional Domain and
Extension repositories mount one level deeper, under `apps/domains/<id>/` and
`apps/extensions/<id>/`, and discovery finds them with no list naming them. A
mounted directory must hold a `bilimbi.container.exs` whose `id` equals the
directory name and whose layer matches its root; it cannot reuse `base`,
`core`, or `web`. The ID is the container's OTP application
name, so its `mix.exs` declares that `app:`. Declared same-layer dependencies
may cross repositories (Domain to Domain, Extension to Extension); upward
edges and cycles are rejected.

Source composition and runtime visibility stay separate. Runtime consumers
read only OTP applications that are loaded, and a package's runtime loads only
its own Mix dependency closure. The Web host closes the gap:
`optional_container_dependencies/1` gives it a path dependency on every mounted
container, so Web's closure, and the `bilimbi` release built around it, is the
whole discovered graph. Every module's metadata records the graph's module
IDs, and `ModuleRegistry.complete_modules!/0` refuses a runtime that has not
loaded all of them. Host boot, the database Mix tasks, and the release
commands call it first; package-local tests may still see a subset through
`installed_modules!/0`.
