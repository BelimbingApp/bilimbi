defmodule BilimbiWeb.ModuleHooksTest do
  use ExUnit.Case, async: false

  require Phoenix.LiveViewTest

  alias BilimbiWeb.ModuleHooks

  @domain Bilimbi.Domain.HookFixture.Web.ProbeLive
  @extension Bilimbi.Extension.HookFixture.Web.Probe
  @clash Bilimbi.Domain.HookFixture.Web.Clash

  setup_all do
    for file <- Path.wildcard(Path.expand("../fixtures/module_hooks/*.ex", __DIR__)) do
      Code.compile_file(file)
    end

    :ok
  end

  setup do
    root = Path.join(System.tmp_dir!(), "bilimbi-hooks-#{System.unique_integer([:positive])}")
    build = Path.join(root, "_build/test")
    File.mkdir_p!(Path.join(root, "apps/web"))
    File.write!(Path.join(root, "mix.exs"), "[]")
    on_exit(fn -> File.rm_rf!(root) end)

    for {container, layer} <- [{"apps/base", :base}, {"apps/core", :core}] do
      put_container!(root, container, Path.basename(container), layer)
    end

    put_app!(build, :web, [])
    %{root: root, build: build}
  end

  test "mounted Domain and Extension hooks with the same local name run in the bundle", context do
    mount!(context, "domains", "hook_fixture", :domain, @domain)
    mount!(context, "extensions", "hook_extension", :extension, @extension)
    assert {:ok, []} = ModuleHooks.write!(context.root, context.build)
    assert {:noop, []} = ModuleHooks.write!(context.root, context.build)

    result = bundled_hooks!(context)
    assert result["Bilimbi.Domain.HookFixture.Web.ProbeLive.Probe"]["moduleHook"] == "mounted"
    assert result["Bilimbi.Extension.HookFixture.Web.Probe.Probe"]["extensionHook"] == "mounted"

    html =
      Phoenix.LiveViewTest.render_component(Function.capture(@domain, :render, 1), flash: %{})

    document = LazyHTML.from_document(html)
    assert Enum.empty?(LazyHTML.query(document, "script"))

    assert document |> LazyHTML.query("#module-hook-probe") |> LazyHTML.attribute("phx-hook") ==
             ["Bilimbi.Domain.HookFixture.Web.ProbeLive.Probe"]
  end

  test "unmount removes hooks despite retained compiled application and extracted files",
       context do
    mount!(context, "domains", "hook_fixture", :domain, @domain)
    ModuleHooks.write!(context.root, context.build)
    assert map_size(bundled_hooks!(context)) == 1

    File.rm_rf!(Path.join(context.root, "apps/domains/hook_fixture"))
    assert {:ok, []} = ModuleHooks.write!(context.root, context.build)
    assert bundled_hooks!(context) == %{}
  end

  test "duplicate fully qualified names fail before an existing entry can be overwritten",
       context do
    mount!(context, "domains", "hook_fixture", :domain, @domain)
    ModuleHooks.write!(context.root, context.build)
    previous = File.read!(Path.join(context.build, "bilimbi-hooks/index.js"))
    mount!(context, "domains", "hook_fixture", :domain, @clash)

    assert_raise Mix.Error,
                 ~r/Colocated hook name clash: Bilimbi.Domain.HookFixture.Web.Clash.Duplicate/,
                 fn ->
                   ModuleHooks.write!(context.root, context.build)
                 end

    assert File.read!(Path.join(context.build, "bilimbi-hooks/index.js")) == previous
  end

  test "missing compiled owners fail clearly rather than silently dropping hooks", context do
    mount!(context, "domains", "hook_fixture", :domain, @domain)

    File.rm!(
      Path.join(context.build, "lib/test_hook_fixture_widget/ebin/test_hook_fixture_widget.app")
    )

    assert_raise Mix.Error, ~r/Cannot collect hooks for hook_fixture\/widget/, fn ->
      ModuleHooks.write!(context.root, context.build)
    end
  end

  defp mount!(context, role, id, layer, module) do
    relative = "apps/#{role}/#{id}"
    put_container!(context.root, relative, id, layer)
    path = Path.join([context.root, relative, "widget"])
    File.mkdir_p!(path)
    app = String.to_atom("test_#{id}_widget")

    namespace =
      if layer == :domain, do: Bilimbi.Domain.HookFixture, else: Bilimbi.Extension.HookFixture

    descriptor = [
      id: "#{id}/widget",
      kind: :module,
      layer: layer,
      required: false,
      otp_app: app,
      namespace: namespace,
      dependencies: [],
      migrations: nil,
      web: nil,
      schema_contract: nil,
      contribution_provider: nil,
      dev_seed: nil
    ]

    File.write!(Path.join(path, "bilimbi.module.exs"), inspect(descriptor))
    put_app!(context.build, app, [module])

    # Compile real HEEx above and copy its extracted asset bytes into this
    # isolated build. The .app resource supplies the same owned-module list
    # compile.app emits, without installing test modules into the host closure.
    for {_component, entries} <- Phoenix.Component.MacroComponent.get_data(module),
        entry <- entries do
      from =
        Path.join([
          Mix.Project.build_path(),
          "phoenix-colocated/web",
          inspect(module),
          entry.filename
        ])

      to =
        Path.join([
          context.build,
          "phoenix-colocated",
          to_string(app),
          inspect(module),
          entry.filename
        ])

      File.mkdir_p!(Path.dirname(to))
      File.cp!(from, to)
    end
  end

  defp put_container!(root, relative, id, layer) do
    path = Path.join(root, relative)
    File.mkdir_p!(path)

    File.write!(
      Path.join(path, "bilimbi.container.exs"),
      inspect(id: id, kind: :container, layer: layer)
    )
  end

  defp put_app!(build, app, modules) do
    file = Path.join([build, "lib", to_string(app), "ebin", "#{app}.app"])
    File.mkdir_p!(Path.dirname(file))
    File.write!(file, :io_lib.format("~p.~n", [{:application, app, [modules: modules]}]))
  end

  defp bundled_hooks!(context) do
    output = Path.join(context.root, "bundle.cjs")

    {result, status} =
      System.cmd(
        Esbuild.bin_path(),
        [
          Path.join(context.build, "bilimbi-hooks/index.js"),
          "--bundle",
          "--platform=node",
          "--outfile=#{output}"
        ],
        env: [{"NODE_PATH", context.build}],
        stderr_to_stdout: true
      )

    assert status == 0, result

    {result, 0} =
      System.cmd("node", [
        "-e",
        """
        const {hooks} = require(process.argv[1]);
        const results = {};
        for (const [name, hook] of Object.entries(hooks)) {
          const el = {dataset: {}, textContent: "Waiting"};
          hook.mounted.call({el});
          results[name] = el.dataset;
        }
        console.log(JSON.stringify(results));
        """,
        output
      ])

    Jason.decode!(result)
  end
end
