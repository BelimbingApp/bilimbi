defmodule BilimbiWeb.RouteOverlapTest do
  use ExUnit.Case, async: true

  alias BilimbiWeb.RouteOverlap

  @checker Path.expand("../../lib/bilimbi_web/route_overlap.ex", __DIR__)

  test "an exact duplicate makes a fixture build fail" do
    assert_build_fails!([
      route("/widgets", :get, {:core, "core/widget"}),
      route("/widgets", :get, {:domain, "domain/widget"})
    ])
  end

  test "a static module route shadowed by a dynamic Core route makes a fixture build fail" do
    assert_build_fails!([
      route("/companies/:id", :get, {:core, "core/company"}),
      route("/companies/export", :get, {:domain, "domain/export"})
    ])
  end

  test "a module dashboard conflicts with the injected host route" do
    assert_build_fails!([
      route("/dashboard", :get, {:web, "web"}),
      route("/dashboard", :get, {:extension, "extension/dashboard"})
    ])
  end

  test "a direct host controller route conflicts with a module controller route" do
    assert_build_fails!([
      %{path: "/api/pins", verb: :get, plug: BilimbiWeb.PinController, metadata: %{}},
      route("/api/pins", :get, {:extension, "extension/pins"})
    ])
  end

  test "a clean route set builds, including distinct verbs and same-owner literal before parameter" do
    routes = [
      route("/users/new", :get, {:core, "core/user"}),
      route("/users/:id", :get, {:core, "core/user"}),
      route("/widgets", :get, {:domain, "domain/widget"}),
      route("/widgets", :post, {:extension, "extension/widget"})
    ]

    assert_build_succeeds!(routes)
  end

  test "glob and catch-all verb overlap controller routes" do
    assert_raise ArgumentError, ~r/route overlap/, fn ->
      RouteOverlap.validate_routes!([
        route("/files/*path", :*, {:core, "core/files"}),
        route("/files/archive/export", :post, {:domain, "domain/export"})
      ])
    end
  end

  test "a same-owner general route compiled before a specific one makes a fixture build fail" do
    assert_build_fails!([
      route("/users/:id", :get, {:core, "core/user"}),
      route("/users/new", :get, {:core, "core/user"})
    ])
  end

  test "same-owner equivalent patterns with different parameter names overlap" do
    assert_raise ArgumentError, ~r/route overlap/, fn ->
      RouteOverlap.validate_routes!([
        route("/users/:id", :get, {:core, "core/user"}),
        route("/users/:user_id", :get, {:core, "core/user"})
      ])
    end
  end

  test "a parameter inside a segment overlaps a matching literal" do
    assert_raise ArgumentError, ~r/route overlap/, fn ->
      RouteOverlap.validate_routes!([
        route("/files/report-:id", :get, {:core, "core/files"}),
        route("/files/report-q3", :get, {:domain, "domain/report"})
      ])
    end

    assert :ok =
             RouteOverlap.validate_routes!([
               route("/files/report-:id", :get, {:core, "core/files"}),
               route("/files/summary", :get, {:domain, "domain/report"})
             ])
  end

  test "a forward route overlaps every path below its prefix" do
    assert_raise ArgumentError, ~r/route overlap/, fn ->
      RouteOverlap.validate_routes!([
        %{path: "/dev/mailbox", verb: :*, kind: :forward, metadata: %{}},
        route("/dev/mailbox/inbox", :get, {:extension, "extension/mail"})
      ])
    end
  end

  test "compiled host routes carry validated descriptor ownership" do
    routes = BilimbiWeb.Router.__routes__()

    assert Enum.any?(routes, fn route ->
             route.path == "/companies/:id" and
               route.metadata[:bilimbi_route_owner] == {:core, "core/company"}
           end)

    assert Enum.any?(routes, fn route ->
             route.path == "/dashboard" and
               route.metadata[:bilimbi_route_owner] == {:web, "web"}
           end)

    assert Enum.any?(routes, fn route ->
             route.path == "/api/pins" and
               is_nil(route.metadata[:bilimbi_route_owner])
           end)
  end

  defp route(path, verb, owner) do
    %{path: path, verb: verb, metadata: %{bilimbi_route_owner: owner}}
  end

  defp assert_build_fails!(routes) do
    {output, status} = compile_fixture(routes)
    assert status != 0
    assert output =~ "route overlap:"
  end

  defp assert_build_succeeds!(routes) do
    {output, status} = compile_fixture(routes)
    assert status == 0, output
  end

  defp compile_fixture(routes) do
    root =
      Path.join(System.tmp_dir!(), "bilimbi-route-fixture-#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(root, "lib"))

    try do
      File.write!(Path.join(root, "mix.exs"), """
      defmodule RouteFixture.MixProject do
        use Mix.Project
        def project, do: [app: :route_fixture, version: "0.1.0", deps: []]
      end
      """)

      File.cp!(@checker, Path.join(root, "lib/route_overlap.ex"))

      File.write!(Path.join(root, "lib/router.ex"), """
      defmodule RouteFixture.Router do
        require BilimbiWeb.RouteOverlap
        @after_compile BilimbiWeb.RouteOverlap
        def __routes__, do: #{inspect(routes, limit: :infinity)}
      end
      """)

      System.cmd("mix", ["compile"], cd: root, stderr_to_stdout: true)
    after
      File.rm_rf!(root)
    end
  end
end
