defmodule BilimbiWeb.RouteRulesTest do
  @moduledoc """
  The rules every module-contributed route obeys, stated once for the whole
  workspace (mounted Domains and Extensions included) instead of pinned per
  module. Pinning a module's list checks that the list has not changed, not
  that the rules hold, and the fix for a failing pin is to paste the new
  entry in.
  """

  use ExUnit.Case, async: true

  alias Bilimbi.Base.ModuleRegistry.MixDiscovery

  @workspace_root Path.expand("../../../..", __DIR__)

  # Open to any signed-in account on purpose: each is the actor's own space
  # (profile, password, appearance, notifications, workspace layout) or the
  # landing page, so there is nothing to grant. Adding a path here is a
  # decision to argue for, not a way to make the rule pass.
  @open_to_signed_in [
    "/dashboard",
    "/workspace",
    "/workspace/shared/:slug",
    "/workspace/:slug",
    "/settings/profile",
    "/settings/password",
    "/settings/appearance",
    "/notifications"
  ]

  defp routes do
    for file <- MixDiscovery.module_route_files(@workspace_root),
        {routes, _binding} = Code.eval_file(file),
        route <- routes,
        do: Map.put(route, :file, Path.relative_to(file, @workspace_root))
  end

  defp where(route), do: "#{route[:path] || route[:embed]} (#{route.file})"

  test "an authenticated page route carries a capability unless it is the actor's own record" do
    offenders =
      for %{path: path, session: :auth} = route <- routes(),
          Map.has_key?(route, :live),
          path not in @open_to_signed_in,
          is_nil(route[:capability]),
          do: where(route)

    assert offenders == [],
           "these authenticated routes are reachable by any signed-in account: #{inspect(offenders)}"
  end

  test "every route's LiveView is a compiled LiveView" do
    offenders =
      for %{live: live} = route <- routes(),
          not (Code.ensure_loaded?(live) and function_exported?(live, :__live__, 0)),
          do: where(route)

    assert offenders == [], "not a compiled LiveView: #{inspect(offenders)}"
  end

  test "every embed names a compiled component" do
    offenders =
      for %{embed: _name} = route <- routes(),
          component = route[:live_component],
          not (is_atom(component) and Code.ensure_loaded?(component) and
                 function_exported?(component, :__live__, 0)),
          do: where(route)

    assert offenders == [], "embed without a compiled component: #{inspect(offenders)}"

    for %{embed: _name} = route <- routes() do
      assert route[:live_component], "embed #{where(route)} names no :live_component"
    end
  end
end
