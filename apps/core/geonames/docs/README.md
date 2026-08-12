# Core Geonames

`core/geonames` owns Bilimbi's compatible geographic reference-data schema and
lookup API. Its physical boundary is this directory and its public namespace is
`Bilimbi.Core.Geonames`.

The compatibility baseline creates the four canonical Belimbing tables:
countries, first-level administrative divisions, postcodes, and cities. Fresh
installation intentionally creates no reference rows; importing and refreshing
the upstream GeoNames datasets is separate seeding work.

Callers use the public facade for country, administrative-division, and
postcode lookups. Table schemas and query details remain private to the module.
