defmodule Bilimbi.Core.User.Migrations.CreateCompatibilityBaseline do
  use Ecto.Migration

  alias Bilimbi.Base.Database.SchemaVerifier

  def up do
    create table(:users, primary_key: false) do
      add :id, :bigserial, primary_key: true

      add :company_id,
          references(:companies,
            type: :bigint,
            on_delete: :nilify_all,
            name: :users_company_id_foreign
          )

      add :employee_id,
          references(:employees,
            type: :bigint,
            on_delete: :nilify_all,
            name: :users_employee_id_foreign
          )

      add :name, :string, null: false
      add :email, :string, null: false
      add :email_verified_at, :naive_datetime
      add :password, :string, null: false
      add :remember_token, :string, size: 100
      timestamps(type: :naive_datetime, null: true, inserted_at: :created_at)
    end

    create unique_index(:users, [:email], name: :users_email_unique)

    # Laravel's password broker keys reset tokens by email, not by user id, so
    # this table has a varchar primary key and no foreign key to users.
    create table(:password_reset_tokens, primary_key: false) do
      add :email, :string, primary_key: true
      add :token, :string, null: false
      add :created_at, :naive_datetime
    end

    create table(:user_pins, primary_key: false) do
      add :id, :bigserial, primary_key: true

      add :user_id,
          references(:users,
            type: :bigint,
            on_delete: :delete_all,
            name: :user_pins_user_id_foreign
          ),
          null: false

      add :label, :string, size: 150, null: false
      add :url, :string, size: 500, null: false
      # MD5 of the normalised URL. Fixed-width char, not varchar: the unique
      # constraint below is the reason the column exists.
      add :url_hash, :char, size: 32, null: false
      add :icon, :string, size: 100
      add :sort_order, :smallint, null: false, default: 0
      timestamps(type: :naive_datetime, null: true, inserted_at: :created_at)
    end

    create unique_index(:user_pins, [:user_id, :url_hash],
             name: :user_pins_user_id_url_hash_unique
           )

    create index(:user_pins, [:user_id, :sort_order])

    create table(:user_database_queries, primary_key: false) do
      add :id, :bigserial, primary_key: true

      add :user_id,
          references(:users,
            type: :bigint,
            on_delete: :delete_all,
            name: :user_database_queries_user_id_foreign
          ),
          null: false

      add :name, :string, size: 150, null: false
      add :slug, :string, size: 200, null: false
      add :prompt, :text
      add :sql_query, :text, null: false
      add :description, :text
      add :icon, :string, size: 100
      timestamps(type: :naive_datetime, null: true, inserted_at: :created_at)
    end

    create unique_index(:user_database_queries, [:user_id, :slug],
             name: :user_database_queries_user_id_slug_unique
           )

    create index(:user_database_queries, [:user_id])

    # Laravel's DatabaseChannel assigns Str::orderedUuid() before insert, so the
    # primary key must be uuid. A bigserial id fails every insert on type.
    create table(:notifications, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :type, :string, null: false
      add :notifiable_type, :string, null: false
      add :notifiable_id, :bigint, null: false
      add :data, :text, null: false
      add :read_at, :naive_datetime
      timestamps(type: :naive_datetime, null: true, inserted_at: :created_at)
    end

    create index(:notifications, [:notifiable_type, :notifiable_id])

    # Completes the `core/user external-access owner` optional group that Core
    # Company declares. Column, index, and foreign key must land together: the
    # verifier reports a partly-present group as an incomplete contribution.
    alter table(:company_external_accesses) do
      add :user_id,
          references(:users,
            type: :bigint,
            on_delete: :nilify_all,
            name: :company_external_accesses_user_id_foreign
          )
    end

    create index(:company_external_accesses, [:user_id, :is_active])
  end

  def down do
    drop index(:company_external_accesses, [:user_id, :is_active])

    execute """
    ALTER TABLE #{quoted_prefix()}.company_external_accesses
    DROP CONSTRAINT company_external_accesses_user_id_foreign
    """

    alter table(:company_external_accesses) do
      remove :user_id
    end

    drop table(:notifications)
    drop table(:user_database_queries)
    drop table(:user_pins)
    drop table(:password_reset_tokens)
    drop table(:users)
  end

  defp quoted_prefix do
    SchemaVerifier.quote_identifier!(prefix() || "public")
  end
end
