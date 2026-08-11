defmodule Bilimbi.Core.CompanyFixtures do
  @moduledoc """
  Lightweight Company fixtures for public-API and web-adapter tests.

  These temporary tables exercise query behavior. Exact PostgreSQL
  compatibility is covered independently by `CompatibilityBaselineTest`.
  """

  alias Bilimbi.Base.Repo
  alias Ecto.Adapters.SQL

  def create_company_identity_tables! do
    SQL.query!(
      Repo,
      """
      CREATE TEMPORARY TABLE tenants (
        id bigint PRIMARY KEY,
        parent_id bigint,
        name varchar(255) NOT NULL,
        status varchar(255) NOT NULL DEFAULT 'active',
        is_platform_operator boolean NOT NULL DEFAULT false,
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
      CREATE TEMPORARY TABLE companies (
        id bigint PRIMARY KEY,
        tenant_id bigint NOT NULL,
        name varchar(255) NOT NULL,
        code varchar(255) NOT NULL UNIQUE,
        status varchar(255) NOT NULL DEFAULT 'active',
        legal_name varchar(255),
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
    attributes =
      Map.merge(
        %{
          id: 41,
          name: "Platform operator",
          status: "active",
          is_platform_operator: true,
          deleted_at: nil
        },
        attributes
      )

    SQL.query!(
      Repo,
      """
      INSERT INTO tenants (id, name, status, is_platform_operator, deleted_at)
      VALUES ($1, $2, $3, $4, $5)
      """,
      [
        attributes.id,
        attributes.name,
        attributes.status,
        attributes.is_platform_operator,
        attributes.deleted_at
      ]
    )
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
end
