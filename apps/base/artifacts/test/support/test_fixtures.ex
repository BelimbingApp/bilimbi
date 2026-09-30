defmodule Bilimbi.Base.Artifacts.TestFixtures do
  @moduledoc false
  alias Bilimbi.Base.Repo

  def create_artifacts_table! do
    Ecto.Adapters.SQL.query!(
      Repo,
      """
      CREATE TEMPORARY TABLE base_artifacts (
        id uuid PRIMARY KEY,
        tenant_id bigint NOT NULL REFERENCES tenants(id) ON DELETE RESTRICT,
        company_id bigint NOT NULL CONSTRAINT base_artifacts_company_positive CHECK (company_id > 0),
        owner_id varchar(255) NOT NULL,
        owner_adapter varchar(255) NOT NULL,
        subject varchar(255) NOT NULL,
        kind varchar(255) NOT NULL,
        content_type varchar(255) NOT NULL,
        byte_size bigint NOT NULL CONSTRAINT base_artifacts_bytes_positive CHECK (byte_size > 0),
        sha256 varchar(64) NOT NULL,
        storage_root text NOT NULL,
        expires_at timestamp(6) NOT NULL,
        ready_at timestamp(6), deleted_at timestamp(6), purged_at timestamp(6),
        purge_attempts integer NOT NULL DEFAULT 0, purge_last_error varchar(255),
        purge_attempted_at timestamp(6), purge_held_at timestamp(6),
        inserted_at timestamp(6) NOT NULL, updated_at timestamp(6) NOT NULL
      ) ON COMMIT PRESERVE ROWS
      """,
      []
    )

    Ecto.Adapters.SQL.query!(
      Repo,
      """
      CREATE INDEX base_artifacts_retention_index ON base_artifacts
        (tenant_id, company_id, owner_id, expires_at)
      """,
      []
    )
  end
end
