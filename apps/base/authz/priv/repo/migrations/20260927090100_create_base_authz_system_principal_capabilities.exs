defmodule Bilimbi.Base.Authz.Migrations.CreateSystemPrincipalCapabilities do
  @moduledoc """
  Bilimbi-only: capabilities granted to named system principals (ADR 0017).

  A system principal is a declared identity a job runs as, such as
  `coating.line_import`, never a user. It holds exactly the capabilities an
  administrator granted it in one company, one row each. There are no deny
  rows, roles, or `grant_all`: absence is refusal, and revocation deletes the
  row. The principal is its declared name, so it cannot share
  `base_authz_principal_capabilities`, whose principals are numeric user and
  agent IDs from Belimbing's schema.

  Like `base_authz_principal_capabilities.company_id`, `company_id` has no
  foreign key; Base Authz validates it against the scope's live companies on
  every grant and every decision.
  """

  use Ecto.Migration

  def change do
    create table(:base_authz_system_principal_capabilities) do
      add :company_id, :bigint, null: false
      add :principal, :string, size: 100, null: false
      add :capability_key, :string, size: 255, null: false
      timestamps(type: :naive_datetime, inserted_at: :created_at)
    end

    create unique_index(
             :base_authz_system_principal_capabilities,
             [:company_id, :principal, :capability_key],
             name: :base_authz_system_principal_caps_unique
           )

    create index(:base_authz_system_principal_capabilities, [:principal])
  end
end
