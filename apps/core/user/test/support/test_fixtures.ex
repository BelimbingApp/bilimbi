defmodule Bilimbi.Core.User.TestFixtures do
  @moduledoc """
  Lightweight User fixtures for public-API tests.

  These temporary tables exercise query behavior. Exact PostgreSQL
  compatibility is covered independently by the schema contract.

  Company and Employee table DDL is not restated here: it is defined once by
  the module that owns it and reused through that module's fixtures.
  """

  alias Bilimbi.Base.Repo
  alias Bilimbi.Core.Employee.TestFixtures, as: EmployeeFixtures
  alias Ecto.Adapters.SQL

  @doc "A valid bcrypt crypt-format hash, so tests never carry a plaintext password."
  def password_hash, do: "$2y$12$" <> String.duplicate("a", 53)

  def create_user_tables! do
    apply(EmployeeFixtures, :create_employee_tables!, [])

    SQL.query!(
      Repo,
      """
      CREATE TEMPORARY TABLE users (
        id bigserial PRIMARY KEY,
        company_id bigint,
        employee_id bigint,
        name varchar(255) NOT NULL,
        email varchar(255) NOT NULL,
        email_verified_at timestamp(0) without time zone,
        password varchar(255) NOT NULL,
        remember_token varchar(100),
        created_at timestamp(0) without time zone,
        updated_at timestamp(0) without time zone
      ) ON COMMIT PRESERVE ROWS
      """,
      []
    )

    # Named explicitly, not an inline UNIQUE. PostgreSQL would name that
    # `users_email_key`, but the migration creates `users_email_unique` and the
    # changeset maps that name to a field error. A fixture that invents its own
    # constraint name turns a caught error into a raised ConstraintError.
    SQL.query!(Repo, "CREATE UNIQUE INDEX users_email_unique ON users (email)", [])
  end

  def insert_user!(attributes \\ %{}) do
    attributes =
      Map.merge(
        %{
          id: 91,
          company_id: 73,
          employee_id: nil,
          name: "Ada Lovelace",
          email: "ada@example.com"
        },
        attributes
      )

    SQL.query!(
      Repo,
      """
      INSERT INTO users (id, company_id, employee_id, name, email, password)
      VALUES ($1, $2, $3, $4, $5, $6)
      """,
      [
        attributes.id,
        attributes.company_id,
        attributes.employee_id,
        attributes.name,
        attributes.email,
        password_hash()
      ]
    )
  end

  def stored_password(user_id) do
    %{rows: [[password]]} =
      SQL.query!(Repo, "SELECT password FROM users WHERE id = $1", [user_id])

    password
  end
end
