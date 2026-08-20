defmodule Bilimbi.Base.Schedule.SchemaContract do
  @moduledoc "Pinned PostgreSQL contract for the Base Schedule compatibility baseline."

  @behaviour Bilimbi.Base.Database.SchemaContract

  alias Bilimbi.Base.Database.SchemaVerifier
  alias Ecto.Adapters.SQL

  @migration_version 20_260_821_100_000
  @statuses ~w(failed running skipped succeeded)

  def migration_version, do: @migration_version

  @impl true
  def tables, do: [runs(), suppressions()]

  @impl true
  def verify_invariants(repo, opts) do
    schema = Keyword.get(opts, :prefix, "public")
    prefix = SchemaVerifier.quote_identifier!(schema)

    unknown =
      SQL.query!(
        repo,
        "SELECT DISTINCT status FROM #{prefix}.base_schedule_runs " <>
          "WHERE status <> ALL($1) ORDER BY status",
        [@statuses]
      ).rows
      |> List.flatten()

    if unknown == [] do
      :ok
    else
      {:error, ["base_schedule_runs: unknown live status values: #{Enum.join(unknown, ", ")}"]}
    end
  end

  defp runs do
    %{
      name: "base_schedule_runs",
      columns: %{
        "id" => column(:bigint, false, {:sequence, "base_schedule_runs_id_seq"}),
        "source" => column({:varchar, 40}, false, {:string, "scheduler"}),
        "key" => column({:varchar, 255}, false),
        "name" => column({:varchar, 255}, false),
        "expression" => column({:varchar, 64}),
        "status" => column({:varchar, 20}, false),
        "started_at" => column({:timestamp, 0}, false),
        "finished_at" => column({:timestamp, 0}),
        "exit_code" => column(:integer),
        "runtime_ms" => column(:integer),
        "output_excerpt" => column(:text),
        "created_at" => column({:timestamp, 0}),
        "updated_at" => column({:timestamp, 0})
      },
      indexes: %{
        "base_schedule_runs_pkey" => index(["id"], true),
        "base_schedule_runs_source_index" => index(["source"]),
        "base_schedule_runs_key_index" => index(["key"]),
        "base_schedule_runs_name_index" => index(["name"]),
        "base_schedule_runs_status_index" => index(["status"]),
        "base_schedule_runs_started_at_index" => index(["started_at"]),
        "base_schedule_runs_task_started_index" => index(["source", "key", "started_at"])
      },
      foreign_keys: %{}
    }
  end

  defp suppressions do
    %{
      name: "base_schedule_suppressions",
      columns: %{
        "id" => column(:bigint, false, {:sequence, "base_schedule_suppressions_id_seq"}),
        "source" => column({:varchar, 40}, false, {:string, "scheduler"}),
        "key" => column({:varchar, 255}, false),
        "name" => column({:varchar, 255}, false),
        "created_at" => column({:timestamp, 0}),
        "updated_at" => column({:timestamp, 0})
      },
      indexes: %{
        "base_schedule_suppressions_pkey" => index(["id"], true),
        "base_schedule_suppressions_source_key_unique" => index(["source", "key"], true)
      },
      foreign_keys: %{}
    }
  end

  defp column(type, nullable \\ true, default \\ nil),
    do: %{type: type, nullable: nullable, default: default}

  defp index(columns, unique \\ false), do: %{columns: columns, unique: unique, where: nil}
end
