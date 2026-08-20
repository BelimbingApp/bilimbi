# base/system

Operator surfaces about the running instance:

- read-only runtime facts at `/system/info`;
- installation language and region management at `/system/localization`;
- the resolved menu contribution inspector at `/system/menu-inspector`.

The first two port Belimbing's Base System Info and Localization screens. Base
System owns their routes, capabilities, and presentation. Base Locale remains
the owner of the supported catalogue, normalization, global persistence, and
provenance rules; the localization screen uses only that public API.

## Localization

`/system/localization` is gated on `admin.system.localization.manage`. It offers
only Base Locale's declared supported catalogue. A manual selection writes the
global locale through `Bilimbi.Base.Locale`, which records `manual` provenance
and clears stale inferred-country state. The page shows the effective language,
source, inferred country, and the shared-UI message catalogues currently
installed. Regional formatting support is stated separately from translated
product copy.

There is deliberately no reset-to-inference action: pinned Belimbing exposes
manual override only, while bootstrap inference runs automatically when there
is no valid stored global locale. Company timezone belongs to the later Base
DateTime capability and is not implemented here.

## System Info

Ports Belimbing's `app/Base/System/Livewire/Info/Index.php` and
`resources/core/views/livewire/admin/system/info/index.blade.php`.

## What differs from the source, and why

- **PHP card becomes Runtime.** `Memory Limit` becomes memory **in use**: the BEAM
  allocates on demand and has no `memory_limit`, so reporting one would be a lie.
  `SAPI`, `Max Execution Time`, `Upload Max Filesize` and `Post Max Size` have no
  single BEAM equivalent and are replaced by facts that answer the same question
  about this runtime -- schedulers, processes against the process limit.
- **PHP Extensions becomes Applications**: loaded OTP applications *with versions*,
  which is the nearest equivalent and strictly more informative.
- **Filesystem card omitted.** Belimbing checks `storage/framework/{cache,sessions,views}`
  and `bootstrap/cache` -- Laravel's own scratch directories. Phoenix has no
  counterpart, and checking invented paths would report health we do not depend on.
  If Bilimbi grows a required writable directory, the card comes back with real paths.
- **Database gains a live connection check**, which #319 asks for and the source
  does not do. Configuration being present says nothing about reachability.
- **The queue row is a live, redacted Base Queue probe.** It reports runtime
  availability plus bounded pending/retryable/discarded counts. It never reads
  or renders arguments, error text, stack traces, or transport configuration.

## Authorization

Gated on `admin.system.info.view`.

Belimbing declares that same capability on its menu item
(`app/Base/System/Config/menu.php:7`) but its **route** omits the `authz:`
middleware (`app/Base/System/Routes/web.php:16`), unlike every neighbouring
system route. Menu-level hiding is not access control, so this screen enforces
the capability Belimbing already declares for it.

## Probes never raise

Every fact returns `:unavailable` rather than failing. Disk figures come from
`:disksup`, which lives in `:os_mon` and is not started in every release -- the
module asks only if it is already running and never starts it as a side effect
of rendering a page.
