defmodule Bilimbi.Base.Session.SchemaContract do
  @moduledoc "Pinned PostgreSQL contract for Belimbing's durable session store."

  @behaviour Bilimbi.Base.Database.SchemaContract

  @migration_version 20_260_811_093_950

  def migration_version, do: @migration_version

  @impl true
  def tables do
    [
      %{
        name: "sessions",
        columns: %{
          "id" => column({:varchar, 255}, false),
          "user_id" => column(:bigint),
          "ip_address" => column({:varchar, 45}),
          "user_agent" => column(:text),
          "payload" => column(:text, false),
          "last_activity" => column(:integer, false)
        },
        indexes: %{
          "sessions_pkey" => index(["id"], true),
          "sessions_user_id_index" => index(["user_id"]),
          "sessions_last_activity_index" => index(["last_activity"])
        },
        foreign_keys: %{}
      }
    ]
  end

  defp column(type, nullable \\ true), do: %{type: type, nullable: nullable, default: nil}
  defp index(columns, unique \\ false), do: %{columns: columns, unique: unique, where: nil}
end
