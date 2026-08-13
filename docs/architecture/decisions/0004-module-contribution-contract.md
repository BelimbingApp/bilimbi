# ADR 0004: Descriptor-owned module contribution providers

**Document Type:** Architecture Decision Record
**Status:** Accepted
**Agents:** codex/sol-high
**Scope:** Installed-module contributions to Settings, Authz, and Menu
**Last Updated:** 2026-08-13

## Context

An installed Bilimbi module must be able to contribute setting definitions,
authorization capabilities, and menu items without editing a central list.
Those three consumers must share one ownership and discovery contract before
their S2 implementations begin.

Belimbing establishes the compatibility behavior, but its discovery mechanism
does not fit Bilimbi's physical module graph. At reference commit
`e70b4d33c0b10790e681f4c2b5095d85a53bc918`, the source inventory contains 22
`menu.php`, 22 `authz.php`, and 12 `settings.php` files below `app/Base` and
`app/Core`. Menu discovery needs six topology-specific glob patterns
(`app/Base/Menu/Services/MenuDiscoveryService.php:26-37`), filters the matched
paths through `DomainState`, and executes each surviving PHP file
(`MenuDiscoveryService.php:43-53,86-121`). Authz likewise scans
topology patterns and requires each file during service registration
(`app/Base/Authz/ServiceProvider.php:109-170`). Settings discovers and executes
module manifests eagerly during boot (`app/Base/Settings/ServiceProvider.php:44-102`).

The useful property is local ownership: adding a module contribution does not
require a central service-provider edit
(`docs/architecture/authorization.md:279-293`). The glob patterns are an
implementation cost of Belimbing not having Bilimbi's installed-module
descriptor graph.

The files are executable PHP rather than inert manifests. For example, Base
Database's menu file captures a parent and builds seven items through a local
function (`app/Base/Database/Config/menu.php:3-70`), while its Settings file
declares and reuses a path validation rule before returning definitions
(`app/Base/Database/Config/settings.php:3-38`). Bilimbi therefore needs a
bounded executable seam, not a claim that all source contributions were
literal data.

Bilimbi already has two relevant precedents:

- `bilimbi.module.exs` owns installed-module facts. Its exact key set is
  validated during Mix graph discovery, then copied into the owning OTP
  application's `:bilimbi_module` metadata
  (`apps/base/module_registry/mix/module_discovery.exs:13-36,92-110,235-247`).
- Production seeds register behavior modules through per-application OTP
  environment and validate provider behavior, owning application, installed
  descriptor, and returned module ID at execution time
  (`apps/base/database/lib/mix/tasks/bilimbi.seeds.run.ex:44-50,73-109`).

Contributions are installed source facts, not deployment configuration and not
an operator override. They are also richer than migration paths: local code may
assemble them, but the registries should receive deterministic data that can be
inspected and validated.

## Decision

### 1. The module descriptor names one contribution provider

The strict `bilimbi.module.exs` schema gains one field:

```elixir
contribution_provider: Bilimbi.Core.User.Contributions
```

The value is either `nil` or one module atom. Every descriptor carries the
field; modules with no contributions use `nil`. The provider must belong to the
descriptor's OTP application.

The descriptor is the authority because a contribution provider is part of
the installed module's source composition. Mix discovery can reject a missing,
duplicate, or non-module field with the rest of the descriptor, include the
choice in the graph fingerprint, and deliver it through the existing runtime
metadata. Runtime coordinators already consume that metadata in resolved module
order (`apps/base/module_registry/lib/module_registry.ex:13-30`).

The contract does **not** add `:bilimbi_menu_items`,
`:bilimbi_capabilities`, or `:bilimbi_setting_definitions` application
environment keys. Application environment remains suitable for operational or
deployment configuration and for the existing explicitly invoked seed runner;
it is not the source of truth for immutable installed-module ownership.

### 2. One provider returns a map keyed by consumer

There is one descriptor field and one provider per module, not three separately
registered provider lists. The provider implements a behavior owned by Base
ModuleRegistry:

```elixir
@callback contributions() :: %{
            optional(:settings) => term(),
            optional(:authz) => term(),
            optional(:menu) => term()
          }
```

`Bilimbi.Base.ModuleRegistry` attaches descriptor provenance to the returned
payload. A provider does not repeat or choose its module ID. The generic loader
accepts only the three known top-level keys and passes `{descriptor, payload}`
pairs to the owning consumer in resolved module order.

The values below `:settings`, `:authz`, and `:menu` are consumer-owned plain
terms. Their exact schemas belong to the Settings, Authz, and Menu contracts;
the generic loader does not merge them and does not impose a generic
last-definition-wins rule. This permits Settings to accept a manifest containing
definitions and explicit runtime-state claims, Authz to accept its domains,
capabilities, and managed system-role declarations, and Menu to accept item
definitions without teaching ModuleRegistry those concepts.

### 3. Providers execute once and yield an immutable plain-term snapshot

The provider behavior is the bounded executable seam. It may use ordinary
Elixir code to assemble constants, which preserves the legitimate capability of
Belimbing's executable config files. Its return value is data: no anonymous
functions, PIDs, ports, references, database queries, network calls, tenant
context, or other process-local state.

If a future consumer needs executable behavior, the returned term names an
explicit module/behavior or MFA-shaped callback that the consumer validates.
It does not carry a closure. Providers must be deterministic, side-effect free,
and safe to invoke during application startup and verification.

ModuleRegistry evaluates each installed provider once per registry build and
holds the resulting immutable snapshot for consumers. Consumers do not call
providers lazily or independently, so one provider cannot return different
definitions to Settings, Authz, and Menu in the same boot.

### 4. Discovery is eager; validation has three deliberate layers

Validation is not deferred to arbitrary first use:

1. **Mix graph discovery** validates the descriptor field as `nil` or a
   non-nil module atom. The provider choice participates in the existing graph
   fingerprint.
2. **Application boot** loads every non-nil provider, proves it implements the
   contribution behavior and belongs to the descriptor's OTP application,
   invokes it once, rejects provider exceptions or unknown top-level keys, and
   asks each consumer to validate its payload. Provider/shape errors, duplicate
   ownership that the consumer forbids, and invalid Settings or Authz
   definitions fail boot with module provenance.
3. **`mix bilimbi.contributions.verify`** runs the same loader and consumer
   validators. It is the deterministic CI/precommit check; it must not contain
   a second, weaker implementation of the rules.

First use may still fail for a caller error. In particular, Settings preserves
the source distinction between an absent stored row and an undeclared key. A
declared setting with no row resolves to its declared default, but registry
lookup for an undeclared definition fails
(`app/Base/Settings/Services/SettingDefinitionRegistry.php:41-47`). Database
reads and writes require either a definition or an explicit runtime-state claim
(`app/Base/Settings/Services/DatabaseSettingsService.php:172-205,218-227,554-563`).
Contribution discovery itself is never lazy.

Consumer semantics remain explicit rather than being distorted into generic
dependency rules. In particular, a menu parent ID is not a module dependency.
Belimbing registers the complete discovered set before validation
(`app/Base/Menu/MenuRegistry.php:34-48`), warns when a parent is absent while
retaining the item (`MenuRegistry.php:56-80`), and then leaves the orphan
unreachable because tree construction selects exact parent IDs
(`app/Base/Menu/MenuBuilder.php:53-74`). Bilimbi Menu preserves that
warn-retain-unreachable behavior. Provider order must not promote or repair an
orphan, and contributors do not add descriptor dependencies merely to order
menu parents.

### 5. Capability keys keep Belimbing's persisted grammar

Capability keys remain lowercase strings in this grammar:

```text
<domain>.<resource-path>.<action>
```

There are at least three dot-separated segments. Each segment starts with a
lowercase letter and then contains lowercase letters, digits, or hyphenated
parts. This is the exact grammar implemented by Belimbing
(`app/Base/Authz/Capability/CapabilityKey.php:8-25`). The Authz consumer also
validates the registered domain and final action/verb, matching the catalog
checks (`app/Base/Authz/Capability/CapabilityCatalog.php:128-144`).

Keys already persist in `base_authz_role_capabilities` and
`base_authz_principal_capabilities`; changing their grammar is a data migration,
not a source rename. Provider validation therefore rejects incompatible keys
instead of silently rewriting them.

### 6. There is no capabilities table and no boot-time grant mutation

Bilimbi preserves Belimbing's deliberate absence of a `capabilities` table.
The in-memory registry is authoritative for known capabilities; persisted role
and principal grants continue to store string keys directly
(`docs/architecture/authorization.md:319-382`). Authorization of an unknown
capability key fails closed; Belimbing enforces this through
`KnownCapabilityPolicy` over the registry's known set
(`app/Base/Authz/Capability/CapabilityRegistry.php:26-50`;
`docs/architecture/authorization.md:210-215`).

Building the contribution snapshot never writes the database. Reconciliation
has these exact boundaries:

- An explicit production-seed or Authz reconciliation command may manage
  configured **system-role** mappings. It diffs desired and existing keys and
  deletes stale rows only for those managed roles, matching
  `app/Base/Authz/Database/Seeders/AuthzRoleCapabilitySeeder.php:22-84`.
- Boot does not add or remove role mappings.
- Principal capability grants are never automatically deleted. A key that is
  no longer contributed remains stored, is denied while unknown, and can become
  effective again if its owning module returns.
- Authz diagnostics must report unknown persisted keys for both role and
  principal grants. Any destructive cleanup is a separate explicit operator
  action, not a side effect of discovery or verification.

This boundary preserves adopted Belimbing data and optional-module
reinstallation while preventing stale keys from authorizing anything.

### 7. Base Settings is the first consumer

Base Settings implements the contract first. It has eager discovery, strict
duplicate ownership, and a clear undeclared-key failure model in the source
(`app/Base/Settings/ServiceProvider.php:44-82` and
`SettingDefinitionRegistry.php:41-70`). It exercises provider loading,
provenance, deterministic snapshots, and consumer validation without first
combining the contract with persisted authorization reconciliation or Menu's
route and tree behavior.

Authz follows Settings, then Menu. Authz adds the persisted-key and explicit
system-role reconciliation rules above. Menu then adds its own collision,
visibility, parent, and rendering rules without changing the shared provider
mechanism.

## Alternatives considered

### Three OTP application-environment keys

Rejected. It follows the production-seed registration precedent superficially,
but it splits one ownership contract across mutable runtime configuration and
allows deployment config to replace installed source facts. It also postpones
all mistakes until runtime and makes it easier for the three consumers to drift.

### Plain contribution payloads inside `bilimbi.module.exs`

Rejected. It would make the structural dependency descriptor carry large,
consumer-specific manifests and would either forbid the legitimate local
computation present in Belimbing or execute that computation at Mix graph
evaluation time. A provider pointer keeps the descriptor small and still makes
ownership explicit.

### One descriptor field per contribution kind

Rejected. Separate fields make partial registration and inconsistent provider
lifecycles possible. One provider gives the installed module one auditable
contribution boundary while retaining separate consumer-owned payloads.

### Filesystem glob discovery

Rejected. Bilimbi already has an installed-module graph and stable descriptor
identity. Reintroducing topology-specific globs would bypass that graph, risk
discovering fixtures or uninstalled source, and recreate the six-pattern cost
visible in Belimbing Menu.

### Lazy provider execution on first use

Rejected. It makes validity depend on which feature a request touches, permits
different consumers to observe different snapshots, and turns deploy-time
contract errors into user-facing failures.

## Consequences

- A module owns all three contribution surfaces without central registration.
- Adding the descriptor field is a coordinated schema change: all installed
  descriptors must gain `contribution_provider: nil` or a provider in the same
  change that updates ModuleRegistry validation and tests.
- Contributions are inspectable terms with stable descriptor provenance, while
  local provider code can still assemble them.
- Registry construction is deterministic and boot-visible. Invalid source does
  not hide until a request exercises it.
- Settings, Authz, and Menu retain their distinct semantic validation instead
  of encoding consumer rules in the generic module graph.
- Capability removal fails closed without destroying adopted role or principal
  grants.
- Future enabled-Domain filtering must occur before provider evaluation and
  must use the same effective module set for all consumers, consistent with ADR
  0003. No optional Domain or Extension implementation is introduced here.
- The implementation task must add the shared verification command to
  precommit and document the descriptor field in `AGENTS.md` section 6. This
  ADR does not claim or edit those product/shared paths.
