defmodule Bilimbi.Base.UI.ClientInputParsingGuardTest do
  @moduledoc """
  Web modules must not call `String.to_integer/1` or `String.to_atom/1` on client input.

  `String.to_integer/1` raises on anything non-numeric, so a forged or empty
  `phx-value-id` crashes the LiveView process rather than being rejected (#376).
  Web handlers should use `Integer.parse/1` (e.g., via a safe `parse_id/1` helper)
  or pass string parameters directly to domain functions that parse safely.

  `String.to_atom/1` on client input creates dynamic atoms and can exhaust the
  BEAM atom table. AGENTS.md rule 7 explicitly forbids calling `String.to_atom/1`
  on user input.

  This test scans all web module source files (`apps/web/lib/**` and
  `apps/*/*/lib/**/web/**`) to ensure neither call appears in web presentation.
  """

  use ExUnit.Case, async: true

  @workspace_root Path.expand("../../../..", __DIR__)

  # Any legitimate exceptions would be listed here relative to workspace root.
  @allowed_paths []

  test "no web module calls String.to_integer or String.to_atom" do
    offenders =
      web_source_files()
      |> Enum.reject(&exempt?/1)
      |> Enum.flat_map(&find_offenses/1)
      |> Enum.sort()

    assert offenders == [],
           """
           These web modules call String.to_integer or String.to_atom:

           #{Enum.map_join(offenders, "\n", &("    " <> &1))}

           `String.to_integer/1` raises ArgumentError on malformed client input,
           crashing the LiveView process. Use `Integer.parse/1` (or a `parse_id/1`
           helper) instead.

           `String.to_atom/1` on untrusted input can exhaust the BEAM atom table.
           Use pattern matching on known string values or atoms instead.
           """
  end

  test "scanner correctly detects AST and line offenses while ignoring comments" do
    sample_clean = """
    defmodule CleanWebLive do
      # Note: String.to_integer/1 and String.to_atom/1 were removed in #376.
      def handle_event("select", %{"id" => id}, socket) do
        case Integer.parse(id) do
          {num, ""} -> {:noreply, assign(socket, :id, num)}
          _ -> {:noreply, socket}
        end
      end
    end
    """

    sample_violator = """
    defmodule ViolatorWebLive do
      def handle_event("click", %{"id" => id}, socket) do
        int_id = String.to_integer(id)
        atom_key = id |> String.to_atom()
        {:noreply, socket}
      end
    end
    """

    sample_clean_heex = ~S"""
    <%!-- <%!-- String.to_integer/1 in comment --%> --%>
    <div>
      <span>{@name}</span> # a trailing comment mentioning String.to_atom
    </div>
    """

    sample_violator_heex = ~S"""
    <div id={"row-#{String.to_integer(@x)}"}>
      <.link phx-value-type={String.to_atom(@type)} />
    </div>
    """

    assert scan_source(sample_clean, "clean.ex") == []
    assert scan_source(sample_clean_heex, "clean.html.heex") == []

    violations = scan_source(sample_violator, "violator.ex")
    assert length(violations) == 2
    assert Enum.any?(violations, &(&1 =~ "violator.ex:3 (String.to_integer)"))
    assert Enum.any?(violations, &(&1 =~ "violator.ex:4 (String.to_atom)"))

    heex_violations = scan_source(sample_violator_heex, "violator.html.heex")
    assert length(heex_violations) == 2
    assert Enum.any?(heex_violations, &(&1 == "violator.html.heex:1"))
    assert Enum.any?(heex_violations, &(&1 == "violator.html.heex:2"))
  end

  defp exempt?(path) do
    relative = Path.relative_to(path, @workspace_root)
    relative in @allowed_paths
  end

  defp web_source_files do
    @workspace_root
    |> Path.join("apps/**/*.{ex,heex}")
    |> Path.wildcard()
    |> Enum.filter(&web_path?/1)
  end

  defp web_path?(path) do
    relative = Path.relative_to(path, @workspace_root)

    not String.contains?(relative, "/test/") and
      (String.starts_with?(relative, "apps/web/lib/") or String.contains?(relative, "/web/"))
  end

  defp find_offenses(path) do
    source = File.read!(path)
    relative = Path.relative_to(path, @workspace_root)
    scan_source(source, relative)
  end

  defp scan_source(source, filename) do
    if String.ends_with?(filename, ".ex") do
      case Code.string_to_quoted(source, file: filename) do
        {:ok, ast} ->
          find_ast_offenses(ast, filename)

        {:error, _} ->
          find_line_offenses(source, filename)
      end
    else
      find_line_offenses(source, filename)
    end
  end

  defp find_ast_offenses(ast, filename) do
    {_ast, offenses} =
      Macro.prewalk(ast, [], fn
        {{:., meta, [{:__aliases__, _, [:String]}, fun]}, _call_meta, _args} = node, acc
        when fun in [:to_integer, :to_atom] ->
          line = Keyword.get(meta, :line, 1)
          formatted = "#{filename}:#{line} (String.#{fun})"
          {node, [formatted | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(offenses)
  end

  defp find_line_offenses(source, filename) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.map(fn {line, num} -> {strip_comments(line), num} end)
    |> Enum.filter(fn {line, _num} ->
      line =~ ~r/\bString\.(to_integer|to_atom)\b/
    end)
    |> Enum.map(fn {_line, num} -> "#{filename}:#{num}" end)
  end

  defp strip_comments(line) do
    line
    |> String.replace(~r/<%!--.*?--%>/, "")
    |> String.replace(~r/#(?!\{).*$/, "")
  end
end
