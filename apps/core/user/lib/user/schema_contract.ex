defmodule Bilimbi.Core.User.SchemaContract do
  @moduledoc """
  Pinned PostgreSQL contract for the Core User compatibility baseline.

  Covers only this module's five tables. The `user_id` contribution to
  `company_external_accesses` is declared by Core Company as an optional group
  and is installed by this module's migration; it is not restated here.
  """

  @behaviour Bilimbi.Base.Database.SchemaContract

  @migration_version 20_260_813_094_500

  def migration_version, do: @migration_version

  @impl true
  def tables do
    [users(), password_reset_tokens(), user_pins(), user_database_queries(), notifications()]
  end

  defp users do
    %{
      name: "users",
      columns: %{
        "id" => column(:bigint, false, {:sequence, "users_id_seq"}),
        "company_id" => column(:bigint),
        "employee_id" => column(:bigint),
        "name" => column({:varchar, 255}, false),
        "email" => column({:varchar, 255}, false),
        "email_verified_at" => column({:timestamp, 0}),
        "password" => column({:varchar, 255}, false),
        "remember_token" => column({:varchar, 100}),
        "created_at" => column({:timestamp, 0}),
        "updated_at" => column({:timestamp, 0})
      },
      indexes: %{
        "users_pkey" => index(["id"], true),
        "users_email_unique" => index(["email"], true)
      },
      foreign_keys: %{
        "users_company_id_foreign" => foreign_key("company_id", "companies", :nilify_all),
        "users_employee_id_foreign" => foreign_key("employee_id", "employees", :nilify_all)
      }
    }
  end

  # Laravel's password broker keys resets by email address, so the primary key
  # is the email and there is deliberately no foreign key to `users`.
  defp password_reset_tokens do
    %{
      name: "password_reset_tokens",
      columns: %{
        "email" => column({:varchar, 255}, false),
        "token" => column({:varchar, 255}, false),
        "created_at" => column({:timestamp, 0})
      },
      indexes: %{"password_reset_tokens_pkey" => index(["email"], true)},
      foreign_keys: %{}
    }
  end

  defp user_pins do
    %{
      name: "user_pins",
      columns: %{
        "id" => column(:bigint, false, {:sequence, "user_pins_id_seq"}),
        "user_id" => column(:bigint, false),
        "label" => column({:varchar, 150}, false),
        "url" => column({:varchar, 500}, false),
        # Fixed-width MD5 of the normalised URL, not varchar.
        "url_hash" => column({:char, 32}, false),
        "icon" => column({:varchar, 100}),
        "sort_order" => column(:smallint, false, {:integer, 0}),
        "created_at" => column({:timestamp, 0}),
        "updated_at" => column({:timestamp, 0})
      },
      indexes: %{
        "user_pins_pkey" => index(["id"], true),
        "user_pins_user_id_url_hash_unique" => index(["user_id", "url_hash"], true),
        "user_pins_user_id_sort_order_index" => index(["user_id", "sort_order"])
      },
      foreign_keys: %{
        "user_pins_user_id_foreign" => foreign_key("user_id", "users")
      }
    }
  end

  defp user_database_queries do
    %{
      name: "user_database_queries",
      columns: %{
        "id" => column(:bigint, false, {:sequence, "user_database_queries_id_seq"}),
        "user_id" => column(:bigint, false),
        "name" => column({:varchar, 150}, false),
        "slug" => column({:varchar, 200}, false),
        "prompt" => column(:text),
        "sql_query" => column(:text, false),
        "description" => column(:text),
        "icon" => column({:varchar, 100}),
        "created_at" => column({:timestamp, 0}),
        "updated_at" => column({:timestamp, 0})
      },
      indexes: %{
        "user_database_queries_pkey" => index(["id"], true),
        "user_database_queries_user_id_slug_unique" => index(["user_id", "slug"], true),
        "user_database_queries_user_id_index" => index(["user_id"])
      },
      foreign_keys: %{
        "user_database_queries_user_id_foreign" => foreign_key("user_id", "users")
      }
    }
  end

  # Laravel's DatabaseChannel assigns Str::orderedUuid() before insert, so the
  # primary key is uuid rather than bigserial, and the polymorphic notifiable
  # pair carries no foreign key.
  defp notifications do
    %{
      name: "notifications",
      columns: %{
        "id" => column(:uuid, false),
        "type" => column({:varchar, 255}, false),
        "notifiable_type" => column({:varchar, 255}, false),
        "notifiable_id" => column(:bigint, false),
        "data" => column(:text, false),
        "read_at" => column({:timestamp, 0}),
        "created_at" => column({:timestamp, 0}),
        "updated_at" => column({:timestamp, 0})
      },
      indexes: %{
        "notifications_pkey" => index(["id"], true),
        "notifications_notifiable_type_notifiable_id_index" =>
          index(["notifiable_type", "notifiable_id"])
      },
      foreign_keys: %{}
    }
  end

  defp column(type, nullable \\ true, default \\ nil) do
    %{type: type, nullable: nullable, default: default}
  end

  defp index(columns, unique \\ false), do: %{columns: columns, unique: unique, where: nil}

  defp foreign_key(column, table, on_delete \\ :cascade) do
    %{
      columns: List.wrap(column),
      references: {table, ["id"]},
      on_delete: on_delete
    }
  end
end
