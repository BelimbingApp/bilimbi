defmodule Bilimbi.Core.Address.PlatformOperatorLocaleBootstrapTest do
  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Locale
  alias Bilimbi.Base.Locale.Bootstrap
  alias Bilimbi.Base.Locale.Contributions, as: LocaleContributions
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Settings.ContributionValidator, as: SettingsValidator
  alias Bilimbi.Base.Settings.TestFixtures, as: SettingsFixtures
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.TestFixtures, as: TenancyFixtures
  alias Bilimbi.Core.Address
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.Employee
  alias Bilimbi.Core.Employee.TestFixtures, as: EmployeeFixtures
  alias Bilimbi.Core.Geonames.TestFixtures, as: GeonamesFixtures

  import Bilimbi.Core.Address.TestFixtures

  setup_all do
    settings =
      SettingsValidator.validate_contributions!([
        %{
          descriptor: %{id: "base/locale"},
          payload: LocaleContributions.contributions().settings
        }
      ])

    ContributionRegistry.put_consumers_for_test!(%{settings: settings}, "address-bootstrap-test")

    on_exit(&ContributionRegistry.clear_for_test!/0)
    :ok
  end

  setup do
    EmployeeFixtures.create_employee_tables!()
    GeonamesFixtures.create_geonames_tables!()
    create_address_tables!()
    SettingsFixtures.create_settings_table!()
    :ok = Employee.ensure_system_types()
    :ok
  end

  describe "platform_operator_locale_bootstrap/0" do
    test "returns nil when no platform operator tenant exists" do
      TenancyFixtures.insert_tenant!(%{
        id: 41,
        name: "Customer Tenant",
        is_platform_operator: false
      })

      CompanyFixtures.insert_company!(%{
        id: 73,
        tenant_id: 41,
        name: "Customer Co",
        code: "customer"
      })

      CompanyFixtures.assign_primary_company!(41, 73)

      GeonamesFixtures.insert_country!(%{
        iso: "DE",
        country: "Germany",
        languages: "de",
        currency_code: "EUR"
      })

      {:ok, scope} = Tenancy.scope(41)

      {:ok, address} =
        Address.create_and_attach_to_company(
          scope,
          73,
          %{label: "HQ", country_iso: "DE"},
          %{is_primary: true}
        )

      assert address.country_iso == "DE"
      assert Address.platform_operator_locale_bootstrap() == nil
    end

    test "returns nil when platform operator tenant has no primary company" do
      TenancyFixtures.insert_tenant!(%{
        id: 41,
        name: "Operator Tenant",
        is_platform_operator: true
      })

      GeonamesFixtures.insert_country!(%{
        iso: "DE",
        country: "Germany",
        languages: "de",
        currency_code: "EUR"
      })

      assert Address.platform_operator_locale_bootstrap() == nil
    end

    test "returns nil when primary company has no attached addresses" do
      TenancyFixtures.insert_tenant!(%{
        id: 41,
        name: "Operator Tenant",
        is_platform_operator: true
      })

      CompanyFixtures.insert_company!(%{
        id: 73,
        tenant_id: 41,
        name: "Operator Co",
        code: "operator"
      })

      CompanyFixtures.assign_primary_company!(41, 73)

      GeonamesFixtures.insert_country!(%{
        iso: "DE",
        country: "Germany",
        languages: "de",
        currency_code: "EUR"
      })

      assert Address.platform_operator_locale_bootstrap() == nil
    end

    test "returns nil when attached address has empty or missing country_iso" do
      TenancyFixtures.insert_tenant!(%{
        id: 41,
        name: "Operator Tenant",
        is_platform_operator: true
      })

      CompanyFixtures.insert_company!(%{
        id: 73,
        tenant_id: 41,
        name: "Operator Co",
        code: "operator"
      })

      CompanyFixtures.assign_primary_company!(41, 73)

      {:ok, scope} = Tenancy.scope(41)

      {:ok, _address} =
        Address.create_and_attach_to_company(
          scope,
          73,
          %{label: "HQ", line1: "1 Main St", country_iso: nil},
          %{is_primary: true}
        )

      assert Address.platform_operator_locale_bootstrap() == nil
    end

    test "resolves Geonames country metadata for the primary company address" do
      TenancyFixtures.insert_tenant!(%{
        id: 41,
        name: "Operator Tenant",
        is_platform_operator: true
      })

      CompanyFixtures.insert_company!(%{
        id: 73,
        tenant_id: 41,
        name: "Operator Co",
        code: "operator"
      })

      CompanyFixtures.assign_primary_company!(41, 73)

      GeonamesFixtures.insert_country!(%{
        iso: "DE",
        country: "Germany",
        languages: "de",
        currency_code: "EUR"
      })

      {:ok, scope} = Tenancy.scope(41)

      {:ok, _address} =
        Address.create_and_attach_to_company(
          scope,
          73,
          %{label: "HQ", country_iso: "DE"},
          %{is_primary: true}
        )

      assert %Bootstrap{
               country_iso: "DE",
               country_name: "Germany",
               languages: "de",
               currency_code: "EUR"
             } = Address.platform_operator_locale_bootstrap()
    end

    test "prioritizes explicit primary address over non-primary address" do
      TenancyFixtures.insert_tenant!(%{
        id: 41,
        name: "Operator Tenant",
        is_platform_operator: true
      })

      CompanyFixtures.insert_company!(%{
        id: 73,
        tenant_id: 41,
        name: "Operator Co",
        code: "operator"
      })

      CompanyFixtures.assign_primary_company!(41, 73)

      GeonamesFixtures.insert_country!(%{
        iso: "DE",
        country: "Germany",
        languages: "de",
        currency_code: "EUR"
      })

      GeonamesFixtures.insert_country!(%{
        iso: "FR",
        country: "France",
        languages: "fr",
        currency_code: "EUR"
      })

      {:ok, scope} = Tenancy.scope(41)

      # Non-primary address attached first with lower priority number
      {:ok, _fr_address} =
        Address.create_and_attach_to_company(
          scope,
          73,
          %{label: "Branch", country_iso: "FR"},
          %{is_primary: false, priority: 1}
        )

      # Explicit primary address attached second
      {:ok, _de_address} =
        Address.create_and_attach_to_company(
          scope,
          73,
          %{label: "HQ", country_iso: "DE"},
          %{is_primary: true, priority: 10}
        )

      assert %Bootstrap{country_iso: "DE", country_name: "Germany"} =
               Address.platform_operator_locale_bootstrap()
    end

    test "falls back to first address by priority when none is marked primary" do
      TenancyFixtures.insert_tenant!(%{
        id: 41,
        name: "Operator Tenant",
        is_platform_operator: true
      })

      CompanyFixtures.insert_company!(%{
        id: 73,
        tenant_id: 41,
        name: "Operator Co",
        code: "operator"
      })

      CompanyFixtures.assign_primary_company!(41, 73)

      GeonamesFixtures.insert_country!(%{
        iso: "DE",
        country: "Germany",
        languages: "de",
        currency_code: "EUR"
      })

      GeonamesFixtures.insert_country!(%{
        iso: "FR",
        country: "France",
        languages: "fr",
        currency_code: "EUR"
      })

      {:ok, scope} = Tenancy.scope(41)

      {:ok, _fr_address} =
        Address.create_and_attach_to_company(
          scope,
          73,
          %{label: "Secondary", country_iso: "FR"},
          %{is_primary: false, priority: 5}
        )

      {:ok, _de_address} =
        Address.create_and_attach_to_company(
          scope,
          73,
          %{label: "Primary by priority", country_iso: "DE"},
          %{is_primary: false, priority: 1}
        )

      assert %Bootstrap{country_iso: "DE", country_name: "Germany"} =
               Address.platform_operator_locale_bootstrap()
    end

    test "returns bootstrap struct with nil languages when country has no languages in Geonames" do
      TenancyFixtures.insert_tenant!(%{
        id: 41,
        name: "Operator Tenant",
        is_platform_operator: true
      })

      CompanyFixtures.insert_company!(%{
        id: 73,
        tenant_id: 41,
        name: "Operator Co",
        code: "operator"
      })

      CompanyFixtures.assign_primary_company!(41, 73)

      GeonamesFixtures.insert_country!(%{
        iso: "ZZ",
        country: "Unknown Land",
        languages: nil,
        currency_code: nil
      })

      {:ok, scope} = Tenancy.scope(41)

      {:ok, _address} =
        Address.create_and_attach_to_company(
          scope,
          73,
          %{label: "HQ", country_iso: "ZZ"},
          %{is_primary: true}
        )

      assert %Bootstrap{
               country_iso: "ZZ",
               country_name: "Unknown Land",
               languages: nil,
               currency_code: nil
             } = Address.platform_operator_locale_bootstrap()
    end

    test "integrates end-to-end with Locale.resolve/2 to infer and persist installation locale" do
      TenancyFixtures.insert_tenant!(%{
        id: 41,
        name: "Operator Tenant",
        is_platform_operator: true
      })

      CompanyFixtures.insert_company!(%{
        id: 73,
        tenant_id: 41,
        name: "Operator Co",
        code: "operator"
      })

      CompanyFixtures.assign_primary_company!(41, 73)

      GeonamesFixtures.insert_country!(%{
        iso: "DE",
        country: "Germany",
        languages: "de",
        currency_code: "EUR"
      })

      {:ok, scope} = Tenancy.scope(41)

      {:ok, _address} =
        Address.create_and_attach_to_company(
          scope,
          73,
          %{label: "HQ", country_iso: "DE"},
          %{is_primary: true}
        )

      bootstrap = Address.platform_operator_locale_bootstrap()
      assert %Bootstrap{country_iso: "DE", languages: "de"} = bootstrap

      # First resolution infers locale and persists provenance
      assert %{
               locale: "de-DE",
               language: "de",
               source: "platform_operator_address",
               inferred_country: "DE"
             } = Locale.resolve(nil, bootstrap)

      # Subsequent resolution without bootstrap reads persisted state
      assert %{
               locale: "de-DE",
               language: "de",
               source: "platform_operator_address",
               inferred_country: "DE"
             } = Locale.resolve(nil)
    end
  end
end
