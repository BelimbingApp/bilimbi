defmodule Bilimbi.Base.ModuleRegistry.CompleteModulesTest do
  # This package's runtime loads only its own dependency closure, which is the
  # partial runtime `complete_modules!/0` exists to refuse. The Web host's
  # test suite proves the complete case.
  use ExUnit.Case, async: false

  alias Bilimbi.Base.ModuleRegistry

  @app :bilimbi_base_module_registry

  test "a package-local runtime sees a subset, and production entry points refuse it" do
    error = assert_raise ArgumentError, fn -> ModuleRegistry.complete_modules!() end

    assert error.message =~ "this runtime cannot see installed modules"
    assert error.message =~ "core/company"
    assert error.message =~ "run from the host application"
  end

  test "names every graph module the runtime is missing" do
    descriptor = Application.fetch_env!(@app, :bilimbi_module)
    graph_ids = descriptor.graph_module_ids

    loaded_ids =
      for {app, _description, _version} <- Application.loaded_applications(),
          loaded = Application.get_env(app, :bilimbi_module),
          do: loaded.id

    error = assert_raise ArgumentError, fn -> ModuleRegistry.complete_modules!() end
    assert error.message =~ Enum.join(graph_ids -- loaded_ids, ", ")
  end

  test "refuses metadata that records no discovered graph" do
    descriptor = Application.fetch_env!(@app, :bilimbi_module)
    on_exit(fn -> Application.put_env(@app, :bilimbi_module, descriptor) end)
    Application.put_env(@app, :bilimbi_module, Map.delete(descriptor, :graph_module_ids))

    assert_raise ArgumentError, ~r/does not record one discovered graph/, fn ->
      ModuleRegistry.complete_modules!()
    end
  end
end
