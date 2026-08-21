defmodule Bilimbi.Core.Address.TestFixtures do
  @moduledoc false

  alias Bilimbi.Base.Repo
  alias Bilimbi.Core.Address.Addressable
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyTestFixtures
  alias Bilimbi.Core.Employee.TestFixtures, as: EmployeeTestFixtures
  alias Bilimbi.Core.Geonames.TestFixtures, as: GeonamesTestFixtures
  alias Ecto.Adapters.SQL

  def create_company_identity_tables! do
    apply(CompanyTestFixtures, :create_company_identity_tables!, [])
  end

  def create_owner_identity_tables! do
    apply(EmployeeTestFixtures, :create_employee_tables!, [])
  end

  def insert_tenant!(attributes \\ %{}) do
    apply(CompanyTestFixtures, :insert_tenant!, [attributes])
  end

  def insert_company!(attributes \\ %{}) do
    apply(CompanyTestFixtures, :insert_company!, [attributes])
  end

  def assign_primary_company!(tenant_id \\ 41, company_id \\ 73) do
    apply(CompanyTestFixtures, :assign_primary_company!, [tenant_id, company_id])
  end

  def create_geonames_tables! do
    apply(GeonamesTestFixtures, :create_geonames_tables!, [])
  end

  def create_settings_table! do
    SQL.query!(
      Repo,
      """
      CREATE TEMPORARY TABLE IF NOT EXISTS base_settings (
        id bigserial PRIMARY KEY,
        key varchar(255) NOT NULL,
        value json NOT NULL,
        is_encrypted boolean NOT NULL DEFAULT false,
        scope_type varchar(50),
        scope_id bigint,
        created_at timestamp(0) without time zone,
        updated_at timestamp(0) without time zone
      ) ON COMMIT PRESERVE ROWS
      """,
      []
    )

    SQL.query!(
      Repo,
      "CREATE UNIQUE INDEX IF NOT EXISTS base_settings_key_scope_unique " <>
        "ON base_settings (key, scope_type, scope_id)",
      []
    )

    SQL.query!(
      Repo,
      "CREATE INDEX IF NOT EXISTS base_settings_scope_type_scope_id_index " <>
        "ON base_settings (scope_type, scope_id)",
      []
    )

    SQL.query!(
      Repo,
      "CREATE UNIQUE INDEX IF NOT EXISTS base_settings_global_key_unique ON base_settings (key) " <>
        "WHERE scope_type IS NULL AND scope_id IS NULL",
      []
    )
  end

  def insert_country!(attributes \\ %{}) do
    apply(GeonamesTestFixtures, :insert_country!, [attributes])
  end

  def insert_admin1!(attributes \\ %{}) do
    apply(GeonamesTestFixtures, :insert_admin1!, [attributes])
  end

  def create_address_tables! do
    SQL.query!(
      Repo,
      """
      CREATE TEMPORARY TABLE IF NOT EXISTS addresses (
        id bigserial PRIMARY KEY,
        label varchar(255),
        phone varchar(255),
        line1 text,
        line2 text,
        line3 text,
        locality varchar(255),
        postcode varchar(255),
        country_iso varchar(2),
        "admin1Code" varchar(20),
        "rawInput" text,
        source varchar(255),
        "sourceRef" varchar(255),
        "parserVersion" varchar(255),
        "parseConfidence" numeric(5,4),
        parsed_at timestamp(0) without time zone,
        normalized_at timestamp(0) without time zone,
        normalization_notes json,
        "verificationStatus" varchar(255) NOT NULL DEFAULT 'unverified',
        metadata json,
        created_at timestamp(0) without time zone,
        updated_at timestamp(0) without time zone,
        deleted_at timestamp(0) without time zone,
        tenant_id bigint NOT NULL,
        CONSTRAINT addresses_country_iso_foreign
          FOREIGN KEY (country_iso) REFERENCES geonames_countries (iso)
          ON DELETE SET NULL,
        CONSTRAINT addresses_admin1code_foreign
          FOREIGN KEY ("admin1Code") REFERENCES geonames_admin1 (code)
          ON DELETE SET NULL
      ) ON COMMIT PRESERVE ROWS
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      CREATE TEMPORARY TABLE IF NOT EXISTS addressables (
        id bigserial PRIMARY KEY,
        address_id bigint NOT NULL,
        addressable_type varchar(255) NOT NULL,
        addressable_id bigint NOT NULL,
        kind json NOT NULL DEFAULT '[]'::json,
        is_primary boolean NOT NULL DEFAULT false,
        priority smallint NOT NULL DEFAULT 0,
        valid_from date,
        valid_to date,
        created_at timestamp(0) without time zone,
        updated_at timestamp(0) without time zone
      ) ON COMMIT PRESERVE ROWS
      """,
      []
    )
  end

  def insert_attachment!(attributes) do
    attributes =
      Map.merge(
        %{
          kind: [],
          is_primary: false,
          priority: 0,
          valid_from: nil,
          valid_to: nil
        },
        attributes
      )

    Addressable
    |> struct!(attributes)
    |> Repo.insert!()
  end

  def soft_delete_address!(address_id) do
    SQL.query!(
      Repo,
      "UPDATE addresses SET deleted_at = '2026-08-12 12:00:00' WHERE id = $1",
      [address_id]
    )
  end
end
