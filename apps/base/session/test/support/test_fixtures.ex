defmodule Bilimbi.Base.Session.TestFixtures do
  @moduledoc false

  alias Bilimbi.Base.Repo
  alias Ecto.Adapters.SQL

  def create_sessions_table! do
    SQL.query!(
      Repo,
      """
      CREATE TEMPORARY TABLE sessions (
        id varchar(255) PRIMARY KEY,
        user_id bigint,
        ip_address varchar(45),
        user_agent text,
        payload text NOT NULL,
        last_activity integer NOT NULL
      ) ON COMMIT DROP
      """,
      []
    )

    SQL.query!(Repo, "CREATE INDEX sessions_user_id_index ON sessions (user_id)", [])

    SQL.query!(
      Repo,
      "CREATE INDEX sessions_last_activity_index ON sessions (last_activity)",
      []
    )
  end
end
