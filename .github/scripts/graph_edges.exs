# Fails when a module's code references a sibling module namespace its
# bilimbi.module.exs does not declare (#567). compile.strict cannot catch
# this: the shared workspace _build puts every sibling on the code path, so an
# undeclared edge compiles clean until someone builds the module standalone.
#
# Standalone escript-style runs, no Mix project and no compilation:
#
#     elixir .github/scripts/graph_edges.exs               # gate the workspace
#     elixir .github/scripts/graph_edges.exs --self-test   # prove the gate
#
# Method: every lib/**/*.ex file is parsed with Code.string_to_quoted/2 and the
# AST is walked for `Bilimbi.<Layer>.<Name>` references — plain aliases, use,
# fully-qualified calls, and grouped aliases (`alias Bilimbi.Base.{A, B}`) all
# count, while moduledocs and comments are strings/absent in the AST, so prose
# mentioning a module cannot false-positive. Aliasing a bare layer
# (`alias Bilimbi.Base`) is rejected outright: it would let later `Base.X`
# references dodge the walk, and the workspace has no legitimate use of it.
# The namespace→id map derives from the descriptors at run time; there is no
# hand-maintained list. `Bilimbi.Base.Repo` maps to base/database per the
# documented AGENTS.md exception.
#
# Known not covered: sibling references inside HEEx (~H sigils and .heex files
# are not Elixir AST). Those are rare and web adapters already declare base/ui.

defmodule GraphEdges do
  @repo_exception [:Bilimbi, :Base, :Repo]
  @layers [:Base, :Core, :Domain, :Extension]

  # Named exceptions — each is a recorded review decision, the same shape as
  # mandates.sh's §13 allowlist, and each admits ONLY the listed namespaces in
  # that one file; any other undeclared reference there still fails. Extending
  # this map is a review decision made in the change that needs it.
  #
  # - contribution_registry.ex names the six consumer validators the ADRs fixed
  #   (AGENTS.md §6; ADR 0004/0009/0011/0012). The consumers depend on the
  #   registry, so these are deliberate reverse edges of the decided seam,
  #   invoked behind Code.ensure_loaded?; declaring them would cycle.
  # - employee's show_live probes Core.User/Core.Address (which both declare
  #   core/employee) via function_exported? — known debt, tracked as #570;
  #   remove this entry when #570 lands a declared seam.
  @file_exceptions %{
    {"base/module_registry", "lib/module_registry/contribution_registry.ex"} => [
      [:Bilimbi, :Base, :Settings],
      [:Bilimbi, :Base, :Authz],
      [:Bilimbi, :Base, :Menu],
      [:Bilimbi, :Base, :Dashboard],
      [:Bilimbi, :Base, :PrincipalDirectory],
      [:Bilimbi, :Base, :Schedule]
    ],
    {"core/employee", "lib/employee/web/show_live.ex"} => [
      [:Bilimbi, :Core, :User],
      [:Bilimbi, :Core, :Address]
    ]
  }

  def main(["--self-test"]), do: SelfTest.run()

  def main(_argv) do
    case violations("apps", @file_exceptions) do
      {:error, message} ->
        IO.puts(:stderr, message)
        System.halt(1)

      [] ->
        IO.puts("graph-edges: every referenced sibling namespace is a declared descriptor edge")

      violations ->
        Enum.each(violations, &IO.puts(:stderr, &1))
        IO.puts(:stderr, "\nDeclare the edge in the module's bilimbi.module.exs dependencies —")
        IO.puts(:stderr, "the descriptor is the contract, and transitive availability is not a declaration.")
        System.halt(1)
    end
  end

  @doc false
  def violations(apps_root, file_exceptions) do
    descriptors = Path.wildcard(Path.join(apps_root, "*/*/bilimbi.module.exs"))

    if descriptors == [] do
      {:error, "FAIL: no module descriptors below #{apps_root}/ — layout changed under this script"}
    else
      modules = Enum.map(descriptors, &load_descriptor/1)

      ns_to_id =
        Map.new(modules, fn m ->
          {Module.split(m.namespace) |> Enum.map(&String.to_atom/1), m.id}
        end)

      modules
      |> Enum.flat_map(&check_module(&1, ns_to_id, file_exceptions))
      |> Enum.uniq()
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

  defp check_module(m, ns_to_id, file_exceptions) do
    self_prefix = Module.split(m.namespace) |> Enum.map(&String.to_atom/1)
    allowed_ids = MapSet.new([m.id | m.deps])

    Path.wildcard(Path.join(m.dir, "lib/**/*.ex"))
    |> Enum.flat_map(fn file ->
      extra_allowed =
        Map.get(file_exceptions, {m.id, Path.relative_to(file, m.dir)}, [])

      file
      |> referenced_prefixes()
      |> Enum.flat_map(fn {prefix, line} ->
        judge(prefix, line, file, m, self_prefix, allowed_ids, ns_to_id, extra_allowed)
      end)
    end)
    |> Enum.uniq()
  end

  # Collects {three_segment_prefix, line} plus {:bare_layer, line} markers.
  # Grouped-alias nodes are replaced with a leaf so their inner __aliases__
  # children (the two-segment base and the one-segment members) are not
  # revisited and double-reported.
  defp referenced_prefixes(file) do
    case file |> File.read!() |> Code.string_to_quoted(columns: false) do
      {:ok, ast} ->
        {_, acc} =
          Macro.prewalk(ast, [], fn
            {{:., _, [{:__aliases__, _, [:Bilimbi | _] = base}, :{}]}, meta, children}, acc ->
              line = meta[:line] || 0

              refs =
                for {:__aliases__, _, child} <- children do
                  classify(base ++ child, line)
                end

              {:__graph_group_handled__, refs ++ acc}

            {:__aliases__, meta, [:Bilimbi, layer]} = node, acc when layer in @layers ->
              {node, [{:bare_layer, meta[:line] || 0} | acc]}

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

  defp classify(segments, line) when length(segments) >= 3,
    do: {Enum.take(segments, 3), line}

  defp classify(_segments, line), do: {:bare_layer, line}

  defp judge(:unparseable, _line, file, m, _self, _allowed, _map, _extra) do
    ["#{m.id}: #{file} could not be parsed; gate cannot certify it"]
  end

  defp judge(:bare_layer, line, file, m, _self, _allowed, _map, _extra) do
    [
      "#{m.id}: #{file}:#{line} aliases a bare layer namespace, which would let " <>
        "later shortened references dodge this gate — alias the full module instead"
    ]
  end

  defp judge(prefix, line, file, m, self_prefix, allowed_ids, ns_to_id, extra_allowed) do
    cond do
      prefix == self_prefix ->
        []

      prefix in extra_allowed ->
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

defmodule SelfTest do
  @moduledoc false
  # Discriminating fixtures: each case plants a defect this gate exists to
  # catch and asserts the gate reports it — or plants an allowed shape and
  # asserts silence. A gate that cannot fail is the defect class half this
  # repository's recent history is about.

  def run do
    root = Path.join(System.tmp_dir!(), "graph_edges_selftest_#{System.unique_integer([:positive])}")

    try do
      write_module!(root, "base/aaa", Bilimbi.Base.Aaa, [])
      write_module!(root, "base/bbb", Bilimbi.Base.Bbb, [])
      write_module!(root, "base/ccc", Bilimbi.Base.Ccc, [])

      results = [
        expect("clean self-reference passes", root, [], fn ->
          lib!(root, "base/aaa", "a.ex", """
          defmodule Bilimbi.Base.Aaa.A do
            @moduledoc "Prose naming Bilimbi.Base.Bbb must not count."
            alias Bilimbi.Base.Aaa
            def go, do: Aaa
          end
          """)
        end),
        expect("plain undeclared alias fails", root, ["base/bbb"], fn ->
          lib!(root, "base/aaa", "a.ex", """
          defmodule Bilimbi.Base.Aaa.A do
            alias Bilimbi.Base.Bbb
            def go, do: Bbb
          end
          """)
        end),
        expect("grouped alias fails", root, ["base/bbb", "base/ccc"], fn ->
          lib!(root, "base/aaa", "a.ex", """
          defmodule Bilimbi.Base.Aaa.A do
            alias Bilimbi.Base.{Bbb, Ccc}
            def go, do: {Bbb, Ccc}
          end
          """)
        end),
        expect("bare layer alias fails", root, ["bare layer"], fn ->
          lib!(root, "base/aaa", "a.ex", """
          defmodule Bilimbi.Base.Aaa.A do
            alias Bilimbi.Base
            def go, do: Base
          end
          """)
        end),
        expect_with_exceptions(
          "exception admits only its listed namespaces",
          root,
          %{{"base/aaa", "lib/a.ex"} => [[:Bilimbi, :Base, :Bbb]]},
          ["base/ccc"],
          ["base/bbb"],
          fn ->
            lib!(root, "base/aaa", "a.ex", """
            defmodule Bilimbi.Base.Aaa.A do
              alias Bilimbi.Base.Bbb
              alias Bilimbi.Base.Ccc
              def go, do: {Bbb, Ccc}
            end
            """)
          end
        )
      ]

      failed = Enum.reject(results, & &1)

      if failed == [] do
        IO.puts("graph-edges self-test: all #{length(results)} fixtures behaved")
      else
        System.halt(1)
      end
    after
      File.rm_rf!(root)
    end
  end

  defp expect(name, root, must_mention, setup),
    do: expect_with_exceptions(name, root, %{}, must_mention, [], setup)

  defp expect_with_exceptions(name, root, exceptions, must_mention, must_not_mention, setup) do
    setup.()
    violations = GraphEdges.violations(Path.join(root, "apps"), exceptions)
    text = violations |> List.wrap() |> Enum.join("\n")

    missing = Enum.reject(must_mention, &String.contains?(text, &1))
    forbidden = Enum.filter(must_not_mention, &String.contains?(text, &1))
    clean_expected = must_mention == []

    cond do
      clean_expected and violations != [] ->
        IO.puts(:stderr, "SELF-TEST FAIL #{name}: expected clean, got\n#{text}")
        false

      missing != [] ->
        IO.puts(:stderr, "SELF-TEST FAIL #{name}: missing #{inspect(missing)} in\n#{text}")
        false

      forbidden != [] ->
        IO.puts(:stderr, "SELF-TEST FAIL #{name}: #{inspect(forbidden)} wrongly reported in\n#{text}")
        false

      true ->
        IO.puts("ok   #{name}")
        true
    end
  end

  defp write_module!(root, id, namespace, deps) do
    dir = Path.join([root, "apps" | String.split(id, "/")])
    File.mkdir_p!(Path.join(dir, "lib"))

    File.write!(Path.join(dir, "bilimbi.module.exs"), """
    [
      id: #{inspect(id)},
      namespace: #{inspect(namespace)},
      dependencies: #{inspect(deps)}
    ]
    """)
  end

  defp lib!(root, id, name, source) do
    File.write!(Path.join([root, "apps" | String.split(id, "/")] ++ ["lib", name]), source)
  end
end

GraphEdges.main(System.argv())
