# Module Contribution Contract — source analysis

**Follows:** [BLB-S1-002](./platform-baseline-inventory.md) §5.2 and §8.3
**Document Type:** Source analysis (read-only)
**Analyst:** claude/opus-5 — source analyst
**Bilimbi Base Commit:** `4146825`
**Belimbing Source:** `/home/kiat/repo/laravel/blb` at `e70b4d33c0b10790e681f4c2b5095d85a53bc918`
**Last Updated:** 2026-08-13

`BLB-S1-002` §8.3 named this the one open question that should be answered
before any S2 implementation starts, because menu, capability, and settings
declaration is **one mechanism serving at least three future modules** — Base
Authz, Base Settings, and Base Menu. If each is ported separately, each invents
its own discovery, and the third one to land inherits two incompatible
precedents.

This analyses the question. It designs nothing and claims no product path. The
decision belongs in an ADR, which is integration-owned.

## 1. What Belimbing actually does

A module contributes behaviour by dropping a file in its own `Config/`
directory. Nothing registers it; a service globs the filesystem for it.

Counts across `app/Base` and `app/Core`: **22 × `menu.php`, 22 × `authz.php`,
12 × `settings.php`**, plus `dashboard.php`, `audit.php`, `pdf.php`,
`locale.php`, and others.

`app/Base/Menu/Services/MenuDiscoveryService.php:28` globs `Config/menu.php`
across layer paths, and its own comments enumerate the shapes it must handle:

```text
app/Base/Menu/Config/menu.php                -> Menu
app/Domains/Commerce/Config/menu.php         -> Commerce   (domain anchor)
app/Core/Geonames/Config/menu.php            -> Geonames   (leaf)
app/Extensions/Ham/Config/menu.php           -> Ham        (source anchor)
app/Extensions/Ham/AutoParts/Config/menu.php -> AutoParts  (package leaf)
```

The payloads are plain data. `app/Core/Employee/Config/menu.php` returns items
carrying `id`, `label`, `icon`, `route`, `permission`, and `parent`;
`app/Core/Employee/Config/authz.php` returns `domains` and a flat `capabilities`
list. `docs/architecture/authorization.md:293` states the contract plainly:
create `Config/authz.php` and the capabilities are registered — "No service
provider changes needed."

**The property worth preserving** is that one file in the owning module is the
whole registration. **The mechanism is not portable**: filesystem globbing over
hard-coded layer paths is precisely what Bilimbi's descriptor graph replaced,
and `MenuDiscoveryService`'s five-way path-shape special-casing is the cost of
having no descriptor.

## 2. Bilimbi already answered this, twice

The question in §8.3 was open when I wrote it. It is now substantially closed by
precedent, and the next task should follow the precedent rather than reopen it.

**Precedent A — the descriptor, for structural facts.** `bilimbi.module.exs`
declares `id`, `kind`, `layer`, `required`, `otp_app`, `namespace`,
`dependencies`, `migrations`, and `schema_contract`. Two of those keys are
already contribution points: `migrations` contributes migration paths and
`schema_contract` contributes a verifiable module. Both are consumed generically
by Compatibility, which "must not hard-code Tenancy, Company, Address, or any
future contributor" (`AGENTS.md` §6).

**Precedent B — OTP application environment, for behaviour.** BLB-S1-008 landed
a second mechanism for a contribution that is a *module implementing a
behaviour* rather than a path or a term:

```elixir
defp discovered_providers do
  ModuleRegistry.installed_modules!()
  |> Enum.flat_map(fn descriptor ->
    descriptor.otp_app |> Application.get_env(:bilimbi_production_seed_provider, []) |> List.wrap()
  end)
end
```

The owning module registers `:bilimbi_production_seed_provider` in its own
application environment; the consumer walks installed descriptors and reads
that key. This is the closest analogue to Belimbing's `Config/*.php` that
respects the descriptor graph — and, unlike globbing, it is explicit, so
`Dev/` fixtures are structurally incapable of being discovered.

**Recommendation: reuse Precedent B for menu, capability, and settings
contributions.** It is proven in-tree, it needs no descriptor schema change, it
composes with `ModuleRegistry`'s ordering and validation, and it keeps
"one declaration in the owning module" — the property that made Belimbing's
version pleasant.

## 3. The three consumers, and how they differ

They are not interchangeable, and an ADR should say so explicitly rather than
treat "contribution" as one uniform thing.

| Consumer | Payload | Validation moment | Failure mode if wrong |
|---|---|---|---|
| **Capabilities** (Base Authz) | Static data — domains and capability key strings | Boot; the set is closed and knowable | A missing capability silently denies, or an unknown key silently grants nothing |
| **Menu** (Base Menu) | Static data — items with `parent` links across modules | Boot for shape; request time for visibility, which depends on the actor | A dangling `parent` orphans an item; a wrong `permission` hides or exposes a route |
| **Settings** (Base Settings) | Definitions — key, scope set, default, type, encryption flag | Boot for definitions; request time for resolution through the scope cascade | An undeclared key resolves to a code default forever, silently |

Two consequences for the contract:

1. **Capabilities and settings definitions are closed sets and should fail
   loudly at boot.** `authorization.md:378` records that Belimbing deliberately
   has *no* capabilities table — the config-driven registry is authoritative,
   so nothing reconciles it against the database. Bilimbi inherits that: if the
   registry is wrong, `base_authz_role_capabilities` rows reference keys that no
   longer exist and nothing notices. A boot-time validation that every persisted
   capability key is still declared is the natural Bilimbi improvement, and it
   is only possible if contributions are discoverable as one set.
2. **Menu is the one with genuine cross-module references.** An item declares
   `parent: "admin.employee"` owned by another module. That is a real ordering
   dependency between contributions, and `ModuleRegistry`'s existing
   dependency-first ordering already supplies the resolution order — another
   reason to key discovery off the descriptor rather than off a glob.

## 4. What the ADR must decide

Stated as questions, because these are decisions and not findings:

1. **One key or three?** A single `:bilimbi_contributions` key returning a map,
   versus `:bilimbi_menu_items`, `:bilimbi_capabilities`,
   `:bilimbi_setting_definitions`. Three keys mirror the seed precedent exactly
   and let a module contribute one without knowing the others exist; one key is
   a single lookup and a single validation pass. I lean to three, on the
   grounds that Belimbing's separate files were separate for the same reason.
2. **Behaviour module or plain term?** Seeds use a behaviour because a seed
   carries a callback. Menu items, capabilities, and settings definitions are
   inert data and could be plain terms in app env. A behaviour buys compile-time
   checking and a place to hang validation; a term is simpler. Note that
   `production_seeds/0` is a function precisely because it must call
   `ModuleRegistry` at runtime to resolve its own module order — a data
   contribution has no such need.
3. **Where does validation fail?** Boot, first use, or a `mix` task. The
   descriptor contract fails "during dependency resolution" (`AGENTS.md` §6);
   the seed runner validates at run time. Capabilities plausibly want boot.
4. **Does the capability key grammar stay Belimbing's?** `authorization.md`
   §5.1 defines it, and persisted rows in `base_authz_role_capabilities` and
   `base_authz_principal_capabilities` are those exact strings. Changing the
   grammar is a data migration, not a naming choice.

## 5. Sequencing consequence

`BLB-S1-002` §7.2 recommended Base Settings first, on the grounds that
`base_settings` has zero foreign keys and both Authz and User preferences read
it. That still holds for *schema*. This analysis adds a constraint on top: the
contribution contract should be decided before **any** of the three lands, but
it only needs to be *implemented* by the first one. So the order is:

1. ADR on the contribution contract — no product path, can start now;
2. Base Settings, implementing the contract for setting definitions;
3. Base Authz, reusing it for capabilities;
4. Base Menu, reusing it for menu items, whenever S3 admits it.

Nothing here changes the S2 dependency order. It adds one small, unblockable
decision task ahead of it — which is the point, since the board currently has
no Ready tasks and at least two agents idle.

## 6. Uncertainties

- I have not read `app/Base/Authz/Services/CapabilityRegistry` or Base Settings'
  definition loader in depth. This analyses the *contribution seam*, not the
  registries behind it; the owning contract tasks still need to.
- Belimbing's `Config/` files also carry `dashboard.php`, `audit.php`,
  `pdf.php`, and `locale.php`. Whether those are the same mechanism or
  coincidental neighbours is unexamined, and they belong to S3 modules that may
  never be admitted.
- Whether Bilimbi wants Belimbing's "no capabilities table" decision at all is
  a real question I have deliberately not answered. It is defensible, and the
  boot-time reconciliation suggested in §3 is the cheaper half of the
  alternative.
