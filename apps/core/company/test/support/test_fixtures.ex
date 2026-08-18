defmodule Bilimbi.Core.Company.TestFixtures do
  @moduledoc """
  Lightweight Company fixtures for public-API and web-adapter tests.

  These temporary tables exercise query behavior. Exact PostgreSQL
  compatibility is covered independently by `Bilimbi.Core.CompatibilityTest`.
  """

  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy.TestFixtures, as: TenancyFixtures
  alias Ecto.Adapters.SQL

  def create_company_identity_tables! do
    apply(TenancyFixtures, :create_tenants_table!, [])

    SQL.query!(
      Repo,
      """
      CREATE TEMPORARY TABLE companies (
        id bigserial PRIMARY KEY,
        parent_id bigint,
        tenant_id bigint NOT NULL,
        name varchar(255) NOT NULL,
        code varchar(255) NOT NULL UNIQUE,
        status varchar(255) NOT NULL DEFAULT 'active',
        legal_name varchar(255),
        registration_number varchar(255),
        tax_id varchar(255),
        legal_entity_type_id bigint,
        jurisdiction varchar(255),
        email varchar(255),
        website varchar(255),
        scope_activities json,
        metadata json,
        created_at timestamp(0) without time zone,
        updated_at timestamp(0) without time zone,
        deleted_at timestamp(0) without time zone
      ) ON COMMIT PRESERVE ROWS
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      CREATE TEMPORARY TABLE tenant_primary_companies (
        tenant_id bigint PRIMARY KEY,
        company_id bigint NOT NULL UNIQUE
      ) ON COMMIT PRESERVE ROWS
      """,
      []
    )
  end

  def insert_tenant!(attributes \\ %{}) do
    apply(TenancyFixtures, :insert_tenant!, [attributes])
  end

  def insert_company!(attributes \\ %{}) do
    attributes =
      Map.merge(
        %{
          id: 73,
          tenant_id: 41,
          name: "Bilimbi Industries",
          code: "bilimbi_industries",
          status: "active",
          legal_name: nil,
          deleted_at: nil
        },
        attributes
      )

    SQL.query!(
      Repo,
      """
      INSERT INTO companies (id, tenant_id, name, code, status, legal_name, deleted_at)
      VALUES ($1, $2, $3, $4, $5, $6, $7)
      """,
      [
        attributes.id,
        attributes.tenant_id,
        attributes.name,
        attributes.code,
        attributes.status,
        attributes.legal_name,
        attributes.deleted_at
      ]
    )
  end

  def assign_primary_company!(tenant_id \\ 41, company_id \\ 73) do
    SQL.query!(
      Repo,
      """
      INSERT INTO tenant_primary_companies (tenant_id, company_id)
      VALUES ($1, $2)
      """,
      [tenant_id, company_id]
    )
  end

  def create_departments_table! do
    create_department_types_table!()

    SQL.query!(
      Repo,
      """
      CREATE TEMPORARY TABLE IF NOT EXISTS company_departments (
        id bigserial PRIMARY KEY,
        company_id bigint NOT NULL,
        department_type_id bigint,
        head_id bigint,
        status varchar(255) NOT NULL DEFAULT 'active',
        metadata json,
        created_at timestamp(0) without time zone,
        updated_at timestamp(0) without time zone
      ) ON COMMIT PRESERVE ROWS
      """,
      []
    )
  end

  def create_department_types_table! do
    SQL.query!(
      Repo,
      """
      CREATE TEMPORARY TABLE IF NOT EXISTS company_department_types (
        id bigserial PRIMARY KEY,
        code varchar(255) NOT NULL,
        name varchar(255) NOT NULL,
        category varchar(255) NOT NULL,
        description text,
        is_active boolean NOT NULL DEFAULT true,
        metadata json,
        created_at timestamp(0) without time zone,
        updated_at timestamp(0) without time zone,
        CONSTRAINT company_department_types_code_unique UNIQUE (code)
      ) ON COMMIT PRESERVE ROWS
      """,
      []
    )
  end

  def create_legal_entity_types_table! do
    SQL.query!(
      Repo,
      """
      CREATE TEMPORARY TABLE IF NOT EXISTS company_legal_entity_types (
        id bigserial PRIMARY KEY,
        code varchar(255) NOT NULL,
        name varchar(255) NOT NULL,
        description text,
        is_active boolean NOT NULL DEFAULT true,
        metadata json,
        created_at timestamp(0) without time zone,
        updated_at timestamp(0) without time zone,
        CONSTRAINT company_legal_entity_types_code_unique UNIQUE (code)
      ) ON COMMIT PRESERVE ROWS
      """,
      []
    )
  end

  def insert_department!(id, company_id, type_id \\ nil) do
    SQL.query!(
      Repo,
      "INSERT INTO company_departments (id, company_id, department_type_id, status) VALUES ($1, $2, $3, 'active')",
      [id, company_id, type_id]
    )
  end

  def create_external_access_tables! do
    SQL.query!(
      Repo,
      """
      CREATE TEMPORARY TABLE IF NOT EXISTS company_relationship_types (
        id bigserial PRIMARY KEY,
        code varchar(255) NOT NULL UNIQUE,
        name varchar(255) NOT NULL,
        description text,
        is_external boolean NOT NULL DEFAULT false,
        is_active boolean NOT NULL DEFAULT true,
        metadata json,
        created_at timestamp(0) without time zone,
        updated_at timestamp(0) without time zone
      ) ON COMMIT PRESERVE ROWS
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      CREATE TEMPORARY TABLE IF NOT EXISTS company_relationships (
        id bigserial PRIMARY KEY,
        company_id bigint NOT NULL,
        related_company_id bigint NOT NULL,
        relationship_type_id bigint NOT NULL,
        effective_from date,
        effective_to date,
        metadata json,
        created_at timestamp(0) without time zone,
        updated_at timestamp(0) without time zone,
        deleted_at timestamp(0) without time zone
      ) ON COMMIT PRESERVE ROWS
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      CREATE TEMPORARY TABLE IF NOT EXISTS company_external_accesses (
        id bigserial PRIMARY KEY,
        company_id bigint NOT NULL,
        relationship_id bigint NOT NULL,
        user_id bigint,
        permissions json,
        is_active boolean NOT NULL DEFAULT true,
        access_granted_at timestamp(0) without time zone,
        access_expires_at timestamp(0) without time zone,
        metadata json,
        created_at timestamp(0) without time zone,
        updated_at timestamp(0) without time zone,
        deleted_at timestamp(0) without time zone
      ) ON COMMIT PRESERVE ROWS
      """,
      []
    )
  end

  def insert_relationship_type!(id \\ 11) do
    SQL.query!(
      Repo,
      "INSERT INTO company_relationship_types (id, code, name, is_active) VALUES ($1, $2, $3, true)",
      [id, "customer_#{id}", "Customer"]
    )
  end

  def insert_relationship!(id, company_id, related_company_id, type_id \\ 11) do
    SQL.query!(
      Repo,
      """
      INSERT INTO company_relationships (id, company_id, related_company_id, relationship_type_id)
      VALUES ($1, $2, $3, $4)
      """,
      [id, company_id, related_company_id, type_id]
    )
  end
end
