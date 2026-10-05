defmodule Bilimbi.Base.UI.WriteGuardOptOutRegistrationTest do
  @moduledoc """
  `#437`: `@write_guard_opt_out` is read from source by the write-handler
  guard, so nothing in the compiled module ever reads it. Without
  `Module.register_attribute(..., persist: true)` in the shared macros,
  the first LiveView or LiveComponent that sets the attribute fails
  `mix compile --warnings-as-errors`.

  This compiles a probe of each shape on `Bilimbi.Base.UI`, the contract
  every module page uses, and proves neither warns.
  """

  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  for shape <- [:live_view, :live_component] do
    @shape shape

    test "a #{@shape} may set @write_guard_opt_out without an unused-attribute warning" do
      unique = System.unique_integer([:positive])

      code = """
      defmodule Bilimbi.Base.UI.WriteGuardOptOutProbe#{unique} do
        use Bilimbi.Base.UI, #{inspect(@shape)}

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
  end
end
