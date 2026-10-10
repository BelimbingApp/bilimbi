# Module-owned development sample data — core/address (#595/#660).
#
# Runs after core/company in dependency order (core/address declares the edge),
# with `scope` and `company_id` bound. Attaches one sample address to the
# operator company so /companies/:id shows a populated address panel rather than
# an empty toolbar — the "harness captures without manual setup" acceptance the
# dev-seed mechanism was built for. Idempotent and dev-only.
alias Bilimbi.Core.Address
alias Bilimbi.Core.Geonames

{:ok, attached} = Address.list_company_attached_addresses(scope, company_id)

# `addresses.country_iso` references the Geonames countries, which a fresh
# database has only after `mix bilimbi.geonames.import`. Until then the
# sample address is left out rather than failing the seed, and so the first
# `mix bilimbi.server`.
unless Enum.any?(attached, &(&1.label == "Head Office")) or
         is_nil(Geonames.get_country("MY")) do
  {:ok, _address} =
    Address.create_and_attach_to_company(
      scope,
      company_id,
      %{
        "label" => "Head Office",
        "line1" => "1 Market Street",
        "locality" => "Kuala Lumpur",
        "country_iso" => "MY"
      },
      %{kind: ["headquarters"], is_primary: true, priority: 1, valid_from: Date.utc_today()}
    )
end
