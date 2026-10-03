defmodule Bilimbi.Base.Workflow.SchemaInvariants do
  @moduledoc false
  alias Bilimbi.Base.Database.SchemaVerifier
  alias Bilimbi.Base.Workflow.SchemaContract
  alias Ecto.Adapters.SQL

  def verify(repo, opts) do
    prefix = Keyword.get(opts, :prefix, "public")
    quoted = SchemaVerifier.quote_identifier!(prefix)
    errors = Enum.flat_map(SchemaContract.tables(), &table_errors(repo, prefix, quoted, &1))

    errors =
      errors ++
        binding_errors(repo, prefix, opts) ++
        Bilimbi.Base.Workflow.CoordinationInvariants.errors(repo, quoted)

    if errors == [], do: :ok, else: {:error, errors}
  end

  defp table_errors(repo, prefix, quoted, spec) do
    table = SchemaVerifier.quote_identifier!(spec.name)
    seq = SchemaVerifier.quote_identifier!(spec.name <> "_id_seq")

    [[sequence]] =
      SQL.query!(repo, "SELECT pg_get_serial_sequence($1, 'id')", [quoted <> "." <> table]).rows

    sequence_errors =
      if sequence == prefix <> "." <> spec.name <> "_id_seq" do
        [[last, called, highest]] =
          SQL.query!(
            repo,
            "SELECT last_value, is_called, (SELECT max(id) FROM #{quoted}.#{table}) FROM #{quoted}.#{seq}",
            []
          ).rows

        if is_nil(highest) or (called and last >= highest) or (not called and last > highest),
          do: [],
          else: ["#{spec.name} sequence would reuse an existing id"]
      else
        ["#{spec.name} id sequence ownership differs"]
      end

    constraints =
      SQL.query!(
        repo,
        """
        SELECT c.conname, c.contype::text, array_agg(a.attname::text ORDER BY k.ordinality)
        FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        CROSS JOIN LATERAL unnest(c.conkey) WITH ORDINALITY k(attnum, ordinality)
        JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = k.attnum
        WHERE n.nspname = $1 AND t.relname = $2 AND c.contype IN ('p', 'u')
        GROUP BY c.conname, c.contype
        """,
        [prefix, spec.name]
      ).rows

    expected =
      for {name, index} <- spec.indexes,
          index.unique,
          do: [name, if(name == spec.name <> "_pkey", do: "p", else: "u"), index.columns]

    constraint_errors =
      if Enum.sort(constraints) == Enum.sort(expected),
        do: [],
        else: ["#{spec.name} primary/unique constraints differ"]

    [[triggers]] =
      SQL.query!(
        repo,
        """
        SELECT count(*) FROM pg_trigger g JOIN pg_class t ON t.oid = g.tgrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE n.nspname = $1 AND t.relname = $2 AND NOT g.tgisinternal
        """,
        [prefix, spec.name]
      ).rows

    trigger_errors = if triggers == 0, do: [], else: ["#{spec.name} has unexpected user triggers"]
    sequence_errors ++ constraint_errors ++ trigger_errors
  end

  defp binding_errors(repo, prefix, opts) do
    [[present]] =
      SQL.query!(
        repo,
        """
        SELECT EXISTS (SELECT 1 FROM pg_class t JOIN pg_namespace n ON n.oid = t.relnamespace
          WHERE n.nspname = $1 AND t.relname = 'base_workflow_subject_bindings')
        """,
        [prefix]
      ).rows

    if present do
      case SchemaVerifier.verify(repo, [binding_table()], opts) do
        :ok -> []
        {:error, errors} -> errors
      end
    else
      []
    end
  end

  def binding_table do
    %{
      name: "base_workflow_subject_bindings",
      columns: %{
        "id" => column(:bigint, {:sequence, "base_workflow_subject_bindings_id_seq"}),
        "tenant_id" => column(:bigint),
        "flow" => column({:varchar, 255}),
        "flow_id" => column(:bigint),
        "subject_type" => column({:varchar, 255}),
        "subject_id" => column({:varchar, 255}),
        "owner" => column({:varchar, 255}),
        "created_at" => column({:timestamp, 0})
      },
      indexes: %{
        "base_workflow_subject_bindings_pkey" => index(["id"]),
        "base_workflow_subject_binding_unique" => index(["flow", "flow_id"]),
        "base_workflow_subject_identity_unique" =>
          index(["tenant_id", "subject_type", "subject_id"])
      },
      foreign_keys: %{
        "base_workflow_subject_bindings_tenant_id_fkey" => %{
          columns: ["tenant_id"],
          references: {"tenants", ["id"]},
          on_delete: :restrict,
          on_update: :nothing
        }
      },
      checks: %{}
    }
  end

  defp column(type, default \\ nil), do: %{type: type, default: default, nullable: false}
  defp index(columns), do: %{columns: columns, unique: true, where: nil}
end
