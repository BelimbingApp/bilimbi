# Base Locale

Base Locale owns Bilimbi's supported regional-locale catalogue and the
`ui.locale` Settings contract. It has no table or migration; values remain in
canonical `base_settings`.

## Resolution contract

Resolution takes an explicit global or user `Bilimbi.Base.Settings.Scope` and
uses this order:

1. explicit user override;
2. valid stored global locale and provenance;
3. one-time inference from bounded platform-operator address facts;
4. declared `en-MY` default.

The higher-layer company owner supplies a `%Bilimbi.Base.Locale.Bootstrap{}`.
Base Locale never queries Company, Address, or Geonames tables and never
derives operator identity from a numeric ID. It persists successful inference
with source `platform_operator_address` and the uppercase country code. Manual
global writes clear that inferred-country state.

## Language and region are different truths

Every supported choice is a regional code such as `en-MY` or `de-CH` so number,
currency, and future date/time formatting can preserve the selected region.
`Bilimbi.Base.Locale.language/1` returns only the language part for a Gettext
adapter.

The current Web Gettext tree contains only the English source/error catalogue;
there are no translated product-copy catalogues. The wider locale catalogue is
formatting support and product policy, not a claim that Bilimbi copy has been
translated into those languages.

No function changes process-global locale state. A Web adapter must apply the
resolved language/region within the lifecycle of its request or LiveView and
must not retain one user's locale for another process.
