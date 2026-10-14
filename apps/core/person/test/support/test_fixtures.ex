defmodule Bilimbi.Core.Person.TestFixtures do
  @moduledoc "Owner-defined identity/affiliation tables for package and real-host tests."
  alias Bilimbi.Base.Repo
  alias Ecto.Adapters.SQL

  def create_person_tables! do
    SQL.query!(
      Repo,
      """
      CREATE TEMPORARY TABLE core_people (
        id bigserial PRIMARY KEY, tenant_id bigint NOT NULL REFERENCES tenants(id),
        full_name varchar(255) NOT NULL, email varchar(255), phone varchar(255),
        retired_at timestamp(0), created_at timestamp(0), updated_at timestamp(0),
        CONSTRAINT core_people_id_tenant_id_index UNIQUE(id, tenant_id)
      ) ON COMMIT PRESERVE ROWS
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      CREATE TEMPORARY TABLE core_person_affiliations (
        id bigserial PRIMARY KEY, tenant_id bigint NOT NULL REFERENCES tenants(id),
        person_id bigint NOT NULL, company_id bigint NOT NULL REFERENCES companies(id),
        title varchar(255), email varchar(255), phone varchar(255), legacy_employee_id bigint UNIQUE,
        unlinked_at timestamp(0), created_at timestamp(0), updated_at timestamp(0),
        CONSTRAINT core_person_affiliations_person_tenant_foreign FOREIGN KEY(person_id, tenant_id)
          REFERENCES core_people(id, tenant_id)
      ) ON COMMIT PRESERVE ROWS
      """,
      []
    )

    SQL.query!(
      Repo,
      "CREATE UNIQUE INDEX core_person_affiliations_live_unique ON core_person_affiliations(person_id, company_id) WHERE unlinked_at IS NULL",
      []
    )
  end
end
