defmodule Bilimbi.Base.UI.RouteContract do
  @moduledoc """
  Compile-time `~p` verification against the workspace route manifest.

  Module LiveViews verify paths here instead of against `BilimbiWeb.Router`,
  so they never depend on the `:web` OTP application.
  """

  @behaviour Phoenix.VerifiedRoutes

  @manifest_path Path.join([
                   Path.expand("../../../../..", __DIR__),
                   "_build",
                   "#{Application.compile_env!(:bilimbi_base_ui, :mix_env)}",
                   "bilimbi_routes.exs"
                 ])
  @external_resource @manifest_path
  # The manifest also carries embed entries (no :path); those belong to
  # Bilimbi.Base.UI.DiscoveredPanels, not to route verification.
  @routes (if File.regular?(@manifest_path) do
             @manifest_path
             |> Code.eval_file()
             |> elem(0)
             |> Enum.filter(&Map.has_key?(&1, :path))
           else
             []
           end)

  @doc """
  The declared GET route path patterns of the workspace, sorted.

  Non-GET entries are excluded: these are the paths a stored navigation
  target, such as a pinned URL, can legitimately point at. Params keep their
  `:name` segment so a caller can match a concrete path against them.
  """
  @spec navigable_paths() :: [String.t()]
  def navigable_paths do
    @routes
    |> Enum.filter(&(Map.get(&1, :verb, :get) == :get))
    |> Enum.map(& &1.path)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  The declared GET route that serves `path`, as `{:ok, route}` with the
  capability its mount requires (`nil` for any signed-in account) and whether
  it is operator-only; `:error` when nothing serves it.

  The same policy `RouteAccess` enforces at mount, asked ahead of time: a
  workspace tile that would only redirect with a refusal can say so in place
  instead. A query string is ignored; only the path decides the route, and
  a URL naming a scheme or host is served by nothing.
  """
  @spec fetch_route(String.t()) ::
          {:ok, %{path: String.t(), capability: String.t() | nil, operator: boolean()}} | :error
  def fetch_route(path) when is_binary(path) do
    case URI.parse(path) do
      %URI{scheme: nil, host: nil, path: "/" <> _ = path} -> fetch_served(path)
      _other -> :error
    end
  end

  defp fetch_served(path) do
    segments = String.split(path, "/", trim: true)

    @routes
    |> Enum.filter(&(Map.get(&1, :verb, :get) == :get))
    |> Enum.find(&Bilimbi.Base.UI.RoutePatterns.match_path?(&1.path, segments))
    |> case do
      nil ->
        :error

      route ->
        {:ok,
         %{path: route.path, capability: route[:capability], operator: route[:operator] == true}}
    end
  end

  @impl true
  def formatted_routes(_opts) do
    Enum.map(@routes, fn route ->
      verb = route |> Map.get(:verb, :get) |> to_string() |> String.upcase()
      %{verb: verb, path: route.path, label: route[:source] || route.path}
    end)
  end

  @impl true
  def verified_route?(_opts, split_path) when is_list(split_path) do
    Enum.any?(@routes, &Bilimbi.Base.UI.RoutePatterns.match_path?(&1.path, split_path))
  end
end
