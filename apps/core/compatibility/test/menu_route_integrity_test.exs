defmodule Bilimbi.Core.MenuRouteIntegrityTest do
  @moduledoc """
  Guards the seam between two independent contributions from the same module:
  its menu items and its routes.

  A module declares navigation through `:menu` contributions and paths through
  `web:`. Nothing connects them, so they can drift silently. `Base.UI.Nav`
  absorbs one half of that drift by refusing to render an item no route serves;
  what it cannot absorb is a menu item whose `capability` disagrees with the
  one guarding its route, which renders a link the router then denies.

  These run against the real installed set rather than fixtures — the drift
  being tested is between modules, so it only exists once they are assembled.
  """

  use ExUnit.Case, async: false

  alias Bilimbi.Base.Menu
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.UI.Nav
  alias Bilimbi.Base.UI.RoutePatterns

  setup_all do
    # Normally installed when the deployment application boots.
    ContributionRegistry.install!()
    :ok
  end

  defp manifest_routes do
    Bilimbi.Base.ModuleRegistry.MixDiscovery.route_manifest_path(
      Path.expand("../../../..", __DIR__)
    )
    |> then(fn path ->
      if File.regular?(path), do: path |> Code.eval_file() |> elem(0), else: []
    end)
  end

  defp find_route(routes, menu_path) do
    split = menu_path |> String.trim_leading("/") |> String.split("/", trim: true)

    Enum.find(routes, fn route ->
      Map.get(route, :verb, :get) == :get and RoutePatterns.match_path?(route.path, split)
    end)
  end

  defp flatten(nodes), do: Enum.flat_map(nodes, &[&1.item | flatten(&1.children)])

  # Belimbing guards a section on the container and leaves its children bare --
  # `app/Core/Geonames/Config/menu.php` puts `admin.geonames.list` on
  # `admin.geonames` and gives Countries/Admin1/Postcodes no permission at all.
  # Visibility is therefore inherited, so an item's effective capability is its
  # own or its nearest ancestor's.
  defp effective_capability(item, by_id) do
    cond do
      item.capability -> item.capability
      is_nil(item.parent) -> nil
      true -> by_id |> Map.get(item.parent) |> then(&(&1 && effective_capability(&1, by_id)))
    end
  end

  test "a menu item's capability matches the capability guarding its route" do
    routes = manifest_routes()
    refute routes == [], "route manifest is empty; the seam under test is not present"

    by_id = Map.new(Menu.items(), &{&1.id, &1})

    mismatches =
      Menu.items()
      |> Enum.filter(& &1.route)
      |> Enum.flat_map(fn item ->
        case find_route(routes, item.route) do
          nil ->
            []

          route ->
            route_capability = Map.get(route, :capability)
            menu_capability = effective_capability(item, by_id)

            if menu_capability == route_capability do
              []
            else
              [
                "#{item.id}: menu #{inspect(menu_capability)} vs route #{inspect(route_capability)}"
              ]
            end
        end
      end)

    # A menu item stricter than its route hides a reachable screen; one looser
    # shows a link the router denies. Neither is a failure anyone sees in tests.
    assert mismatches == [],
           "menu and route capabilities disagree:\n  " <> Enum.join(mismatches, "\n  ")
  end

  test "the sidebar offers no link the router cannot serve" do
    routes = manifest_routes()

    # An actor holding every declared capability sees the widest possible tree,
    # so this covers every item any actor could reach.
    scope = %{capabilities: Enum.flat_map(Menu.items(), &List.wrap(&1.capability))}

    unreachable =
      scope
      |> Nav.tree()
      |> flatten()
      |> Enum.filter(& &1.route)
      |> Enum.reject(&find_route(routes, &1.route))
      |> Enum.map(&"#{&1.id} -> #{&1.route}")

    assert unreachable == [],
           "the sidebar would render links that 404:\n  " <> Enum.join(unreachable, "\n  ")
  end

  test "the installed modules do produce a navigable sidebar" do
    # The pruning above fails safe: a mistake in it, or a manifest that failed
    # to write, empties the sidebar rather than breaking a page. That is the
    # regression this catches, and it is one nothing else would report.
    scope = %{capabilities: Enum.flat_map(Menu.items(), &List.wrap(&1.capability))}

    rendered = scope |> Nav.tree() |> flatten() |> Enum.filter(& &1.route)

    refute rendered == [], "no installed module contributes a reachable menu item"
  end
end
