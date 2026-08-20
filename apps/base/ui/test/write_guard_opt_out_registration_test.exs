defmodule Bilimbi.Base.UI.WriteGuardOptOutRegistrationTest do
  @moduledoc """
  `#437`: `@write_guard_opt_out` is read from source by the write-handler
  guard, so nothing in the compiled module ever reads it. Without
  `Module.register_attribute(..., persist: true)` in the shared macros,
  the first LiveView or LiveComponent that sets the attribute fails
  `mix compile --warnings-as-errors`.

  `#435` registered the LiveView quotes only. This test pins both shapes
  in both public adapters, and proves a LiveComponent opt-out compiles
  clean.
  """

  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  @adapters [
    {"apps/base/ui/lib/ui.ex", Path.expand("../lib/ui.ex", __DIR__)},
    {"apps/web/lib/bilimbi_web.ex", Path.expand("../../../web/lib/bilimbi_web.ex", __DIR__)}
  ]

  for {label, path} <- @adapters do
    @label label
    @path path

    test "#{@label} registers write_guard_opt_out on live_view and live_component" do
      source = File.read!(@path)
      assert {:ok, ast} = Code.string_to_quoted(source, file: @path)

      for shape <- [:live_view, :live_component] do
        assert registers_write_guard_opt_out?(ast, shape),
               "#{@label} #{shape}/0 must call Module.register_attribute(__MODULE__, :write_guard_opt_out, persist: true)"
      end
    end
  end

  test "a LiveComponent may set @write_guard_opt_out without an unused-attribute warning" do
    unique = System.unique_integer([:positive])

    code = """
    defmodule Bilimbi.Base.UI.WriteGuardOptOutLiveComponentProbe#{unique} do
      use Bilimbi.Base.UI, :live_component

      # UI-state toggle — write-shaped by name only (#437 compile probe).
      @write_guard_opt_out ~w(toggle_dropdown)

      @impl true
      def render(assigns), do: ~H\"\"\"
      <div id="write-guard-opt-out-probe" />
      \"\"\"
    end
    """

    warnings =
      capture_io(:stderr, fn ->
        assert [_ | _] = Code.compile_string(code)
      end)

    refute warnings =~ "write_guard_opt_out"
    refute warnings =~ "never used"
  end

  defp registers_write_guard_opt_out?(ast, shape) do
    ast
    |> Macro.prewalk(false, fn
      {:def, _, [{^shape, _, _}, [do: body]]}, false ->
        {body, quote_registers_opt_out?(body)}

      node, found ->
        {node, found}
    end)
    |> elem(1)
  end

  defp quote_registers_opt_out?(body) do
    body
    |> Macro.prewalk(false, fn
      {{:., _, [{:__aliases__, _, [:Module]}, :register_attribute]}, _,
       [{:__MODULE__, _, _}, :write_guard_opt_out, opts]},
      false
      when is_list(opts) ->
        {nil, Keyword.get(opts, :persist) == true}

      node, found ->
        {node, found}
    end)
    |> elem(1)
  end
end
