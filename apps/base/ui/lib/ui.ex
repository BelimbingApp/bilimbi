defmodule Bilimbi.Base.UI do
  @moduledoc """
  Shared presentation contracts for module-owned web adapters.

  Module LiveViews `use Bilimbi.Base.UI, :live_view` instead of
  `use BilimbiWeb, :live_view`. This package is dependency-light: Phoenix
  libraries and `base/module_registry` only. Authentication hooks stay in
  `BilimbiWeb.UserAuth`.
  """

  @doc """
  Whether the scope (or assign map) lists `capability` among its effective allows.
  """
  @spec allowed?(map() | nil, String.t()) :: boolean()
  def allowed?(%{capabilities: capabilities}, capability)
      when is_list(capabilities) and is_binary(capability) do
    capability in capabilities
  end

  def allowed?(_current_scope, _capability), do: false

  def live_view do
    quote do
      use Phoenix.LiveView
      use Bilimbi.Base.UI.ActionFailureRecovery, :live_view

      # `@write_guard_opt_out` is read from source by
      # apps/base/ui/test/write_handler_guard_test.exs, so nothing in the
      # compiled module ever reads it and Elixir warns "set but never used" --
      # which fails CI's `mix compile --warnings-as-errors`. Registering it
      # marks it as used and makes the documented opt-out usable at all (#437).
      Module.register_attribute(__MODULE__, :write_guard_opt_out, persist: true)

      unquote(html_helpers())
    end
  end

  def live_component do
    quote do
      use Phoenix.LiveComponent
      use Bilimbi.Base.UI.ActionFailureRecovery, :live_component

      # Same registration as `:live_view` — opt-out is documented for both
      # adapter shapes (#437).
      Module.register_attribute(__MODULE__, :write_guard_opt_out, persist: true)

      unquote(html_helpers())
    end
  end

  def html do
    quote do
      use Phoenix.Component

      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      use Gettext, backend: Bilimbi.Base.UI.Gettext

      import Phoenix.HTML
      import Bilimbi.Base.UI, only: [allowed?: 2]
      import Bilimbi.Base.UI.Components
      import Bilimbi.Base.UI.DiscoveredPanels, only: [discovered_panel: 1]

      alias Bilimbi.Base.UI.Layouts
      alias Phoenix.LiveView.JS

      use Phoenix.VerifiedRoutes,
        router: Bilimbi.Base.UI.RouteContract,
        endpoint: Bilimbi.Base.UI.ScriptPath,
        statics: ~w(assets fonts images favicon.ico favicon.svg robots.txt)
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
