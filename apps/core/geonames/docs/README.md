# Core Geonames

`core/geonames` owns Bilimbi's compatible geographic reference-data schema and
lookup API. Its physical boundary is this directory and its public namespace is
`Bilimbi.Core.Geonames`.

The compatibility baseline creates the four canonical Belimbing tables:
countries, first-level administrative divisions, postcodes, and cities. Fresh
installation intentionally creates no reference rows; imports remain an
explicit operational action:

```bash
mix bilimbi.geonames.import
mix bilimbi.geonames.import --postcodes MY,SG
```

Countries, administrative divisions, and cities import by default. Postcodes
are opt-in because their size varies substantially by country. Downloads use
ETag-aware caching with a seven-day modification-time fallback. Set a durable
cache with `--cache-dir`; the default is the operating system temporary
directory.

Imports stream and batch rows rather than loading global datasets into memory.
Each dataset import is atomic: a database failure in any batch rolls the whole
dataset back and surfaces as `{:error, {:import, dataset, {:database, _}}}`,
and a payload with no valid rows is rejected with
`{:error, {:import, dataset, :no_valid_rows}}`. A failed import restores the
previously known-good download cache. Country and administrative-division
names are preserved when locally edited, while postcode refreshes replace one
country's rows transactionally.

Callers use the public facade for country, administrative-division, and
postcode lookups. Table schemas and query details remain private to the module.
