# Fails when a module's code references a sibling module namespace its
# bilimbi.module.exs does not declare (#567). compile.strict cannot catch
# this: the shared workspace _build puts every sibling on the code path, so an
# undeclared edge compiles clean until someone builds the module standalone.
#
# Standalone escript-style run, no Mix project and no compilation:
#
#     elixir .github/scripts/graph_edges.exs
#
# Method: every lib/**/*.ex file is parsed with Code.string_to_quoted/2 and the
# AST is walked for `Bilimbi.<Layer>.<Name>` alias nodes — aliases, use, and
# fully-qualified calls all appear as such nodes, while moduledocs and comments
# are strings/absent in the AST, so prose mentioning a module cannot false-
# positive. The namespace→id map is derived from the descriptors at run time;
# there is no hand-maintained list. `Bilimbi.Base.Repo` maps to base/database
# per the documented AGENTS.md exception.
#
# Known not covered: sibling references inside HEEx (~H sigils and .heex files
# are not Elixir AST). Those are rare and web adapters already declare base/ui.

defmodule GraphEdges do
  @repo_exception [:Bilimbi, :Base, :Repo]

  # Named exceptions — each is a recorded review decision, the same shape as
  # mandates.sh's §13 allowlist. An entry admits references from that one file;
  # extending this map is a review decision made in the change that needs it.
  #
  # - contribution_registry.ex names the six consumer validators the ADRs fixed
  #   (AGENTS.md §6; ADR 0004/0009/0011/0012). The consumers depend on the
  #   registry, so these are deliberate reverse edges of the decided seam,
  #   invoked behind Code.ensure_loaded?; declaring them would cycle.
  # - employee's show_live probes Core.User/Core.Address (which both declare
  #   core/employee) via function_exported? — known debt, tracked as #570;
  #   remove this entry when #570 lands a declared seam.
  @file_exceptions %{
    {"base/module_registry", "lib/module_registry/contribution_registry.ex"} =>
      "ADR-fixed consumer-validator seam",
    {"core/employee", "lib/employee/web/show_live.ex"} =>
      "reverse-edge probing pending #570"
  }

  def run do
    descriptors = Path.wildcard("apps/*/*/bilimbi.module.exs")

    if descriptors == [] do
      IO.puts(:stderr, "FAIL: no module descriptors below apps/ — layout changed under this script")
      System.halt(1)
    end

    modules = Enum.map(descriptors, &load_descriptor/1)

    ns_to_id =
      Map.new(modules, fn m -> {Module.split(m.namespace) |> Enum.map(&String.to_atom/1), m.id} end)

    violations = Enum.flat_map(modules, &check_module(&1, ns_to_id))

    case violations do
      [] ->
        IO.puts("graph-edges: every referenced sibling namespace is a declared descriptor edge")

      _ ->
        Enum.each(violations, &IO.puts(:stderr, &1))
        IO.puts(:stderr, "\nDeclare the edge in the module's bilimbi.module.exs dependencies —")
        IO.puts(:stderr, "the descriptor is the contract, and transitive availability is not a declaration.")
        System.halt(1)
    end
  end

  defp load_descriptor(path) do
    {opts, _} = Code.eval_file(path)

    %{
      id: Keyword.fetch!(opts, :id),
      namespace: Keyword.fetch!(opts, :namespace),
      deps: Keyword.get(opts, :dependencies) || [],
      dir: Path.dirname(path)
    }
  end

  defp check_module(m, ns_to_id) do
    self_prefix = Module.split(m.namespace) |> Enum.map(&String.to_atom/1)
    allowed_ids = MapSet.new([m.id | m.deps])

    Path.wildcard(Path.join(m.dir, "lib/**/*.ex"))
    |> Enum.reject(fn file ->
      Map.has_key?(@file_exceptions, {m.id, Path.relative_to(file, m.dir)})
    end)
    |> Enum.flat_map(fn file ->
      file
      |> referenced_prefixes()
      |> Enum.flat_map(fn {prefix, line} ->
        judge(prefix, line, file, m, self_prefix, allowed_ids, ns_to_id)
      end)
    end)
    |> Enum.uniq()
  end

  defp referenced_prefixes(file) do
    case file |> File.read!() |> Code.string_to_quoted(columns: false) do
      {:ok, ast} ->
        {_, acc} =
          Macro.prewalk(ast, [], fn
            {:__aliases__, meta, [:Bilimbi, layer, name | _]} = node, acc
            when is_atom(layer) and is_atom(name) ->
              {node, [{[:Bilimbi, layer, name], meta[:line] || 0} | acc]}

            node, acc ->
              {node, acc}
          end)

        acc

      {:error, _} ->
        # A lib file the Elixir parser rejects would already fail compilation;
        # report it so the gate never silently skips a file.
        [{:unparseable, 0}]
    end
  end

  defp judge(:unparseable, _line, file, m, _self, _allowed, _map) do
    ["#{m.id}: #{file} could not be parsed; gate cannot certify it"]
  end

  defp judge(prefix, line, file, m, self_prefix, allowed_ids, ns_to_id) do
    cond do
      prefix == self_prefix ->
        []

      prefix == @repo_exception ->
        if MapSet.member?(allowed_ids, "base/database"),
          do: [],
          else: [violation(m, file, line, "Bilimbi.Base.Repo", "base/database")]

      id = ns_to_id[prefix] ->
        if MapSet.member?(allowed_ids, id),
          do: [],
          else: [violation(m, file, line, Enum.join(prefix, "."), id)]

      true ->
        [
          "#{m.id}: #{file}:#{line} references #{Enum.join(prefix, ".")}, which is no " <>
            "installed module namespace — a typo, or a module this workspace does not know"
        ]
    end
  end

  defp violation(m, file, line, ns, id) do
    "#{m.id}: #{file}:#{line} references #{ns} (#{id}) but bilimbi.module.exs does not declare it"
  end
end

GraphEdges.run()
