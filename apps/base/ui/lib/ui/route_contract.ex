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
  @routes (if File.regular?(@manifest_path) do
             elem(Code.eval_file(@manifest_path), 0)
           else
             []
           end)

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
