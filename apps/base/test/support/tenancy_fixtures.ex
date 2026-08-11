defmodule Bilimbi.Base.TenancyFixtures do
  @moduledoc false

  alias Bilimbi.Base.Repo
  alias Ecto.Adapters.SQL

  def create_tenants_table! do
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
  end

  def insert_tenant!(attributes \\ %{}) do
    attributes =
      Map.merge(
        %{
          id: 41,
          parent_id: nil,
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
      INSERT INTO tenants (
        id, parent_id, name, status, is_platform_operator, deleted_at
      )
      VALUES ($1, $2, $3, $4, $5, $6)
      """,
      [
        attributes.id,
        attributes.parent_id,
        attributes.name,
        attributes.status,
        attributes.is_platform_operator,
        attributes.deleted_at
      ]
    )
  end
end
