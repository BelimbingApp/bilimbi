defmodule Bilimbi.Base.Database.RawSqlWriteGuardTest do
  @moduledoc """
  Raw SQL is the one write path `Bilimbi.Base.Repo` cannot capture, and
  ADR 0013 keeps it **empty of auditable writes** rather than covering it.
  That is only true while it stays true, so this test is the thing that
  keeps it so: a DML statement handed to `Ecto.Adapters.SQL.query/3` or
  `query!/3` may appear only in the lifecycle modules listed below.

  The rule is not "no raw SQL". Schema verification, adoption, cutover,
  advisory locks and the seed ledger all need it, and none of them writes
  business data. The rule is that a **write** through raw SQL is a decision
  someone takes deliberately, in a module named here, with a reason beside
  it — and never something that turns up in a domain module because it was
  convenient.

  ## How it reads the tree

  From the AST, not a grep. A heredoc spanning twelve lines is one string
  to the parser and three unrelated lines to a line-oriented search, which
  is how a multi-line `INSERT` would slip past one. Only string arguments
  to those two calls are scanned, so `NaiveDateTime.truncate/2` and the
  console's own forbidden-keyword list — the words `TRUNCATE` and `DELETE`
  in Elixir code that issues no SQL — are not findings.

  Interpolated SQL parses as a binary with holes in it; the literal
  fragments around the holes are scanned, which is enough, because the
  verb is never the interpolated part.

  ## Adding an entry

  A new allowlist entry needs a comment saying what the module writes and
  why it cannot be an Ecto write. If the answer is "it could be, it just
  was not", that is the fix, not the entry.
  """

  use ExUnit.Case, async: true

  @workspace_root Path.expand("../../../..", __DIR__)

  # Lifecycle modules that legitimately write through raw SQL. Every one is
  # on the "must not audit" side of the trail: none of them records a
  # business decision, and most run before or outside a request entirely.
  @allowed %{
    # The production-seed ledger: which seeds ran, in which order, with
    # what status. It is written before the schema it seeds is complete,
    # and the whole run is inside `WriteCapture.without_capture/1` anyway.
    "apps/base/database/lib/database/production_seeds.ex" => "seed ledger bookkeeping",

    # Cutover rewrites an existing Belimbing database into the compatible
    # baseline, translating payloads across tables Ecto has no schema for.
    "apps/core/compatibility/lib/compatibility/cutover.ex" => "cutover payload translation"
  }

  @dml ~r/\b(INSERT\s+INTO|UPDATE\s+[\w."#{}]+\s+SET|DELETE\s+FROM|TRUNCATE|MERGE\s+INTO|COPY\s+[\w."#{}]+\s+FROM)\b/i

  test "raw-SQL DML appears only in the allowlisted lifecycle modules" do
    offenders =
      source_files()
      |> Enum.flat_map(&raw_sql_writes/1)
      |> Enum.reject(fn {path, _line, _statement} -> Map.has_key?(@allowed, path) end)
      |> Enum.sort()

    assert offenders == [],
           """
           Raw SQL bypasses the repo's write capture, so an audited write cannot be made this way
           (ADR 0013). Use the repo — `insert_all`, `update_all`, `delete_all` and the struct
           writes are all captured — or, if this really is lifecycle machinery that must not be
           audited, add the module to @allowed in this file with the reason.

           #{Enum.map_join(offenders, "\n", fn {path, line, statement} -> "  #{path}:#{line} #{statement}" end)}
           """
  end

  test "every allowlisted module still exists and still writes raw SQL" do
    stale =
      Enum.reject(@allowed, fn {path, _reason} ->
        @workspace_root |> Path.join(path) |> raw_sql_writes() != []
      end)

    assert stale == [],
           """
           An allowlist entry that no longer writes raw SQL is a licence nobody is using.
           Delete it:

           #{Enum.map_join(stale, "\n", fn {path, reason} -> "  #{path} (#{reason})" end)}
           """
  end

  defp source_files do
    ["apps/*/*/lib/**/*.ex", "apps/web/lib/**/*.ex"]
    |> Enum.flat_map(&Path.wildcard(Path.join(@workspace_root, &1)))
    |> Enum.uniq()
  end

  defp raw_sql_writes(path) do
    relative = Path.relative_to(path, @workspace_root)

    path
    |> File.read!()
    |> Code.string_to_quoted!(columns: true, literal_encoder: &{:ok, {:__block__, &2, [&1]}})
    |> Macro.prewalk([], &collect_sql_call/2)
    |> elem(1)
    |> Enum.filter(fn {_line, statement} -> Regex.match?(@dml, statement) end)
    |> Enum.map(fn {line, statement} -> {relative, line, excerpt(statement)} end)
  end

  defp collect_sql_call({{:., _, [{:__aliases__, _, aliases}, name]}, meta, args} = node, found)
       when name in [:query, :query!] do
    if List.last(aliases) == :SQL do
      {node, found ++ Enum.map(statements(args), &{meta[:line], &1})}
    else
      {node, found}
    end
  end

  defp collect_sql_call(node, found), do: {node, found}

  # The literal parts of every string argument, interpolated or not.
  defp statements(args), do: Enum.flat_map(args, &literal_binary/1)

  defp literal_binary({:__block__, _meta, [value]}) when is_binary(value), do: [value]

  defp literal_binary({:<<>>, _meta, parts}) do
    parts
    |> Enum.filter(&is_binary/1)
    |> Enum.join(" ")
    |> List.wrap()
  end

  defp literal_binary(_other), do: []

  defp excerpt(statement) do
    statement
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.slice(0, 90)
  end
end
