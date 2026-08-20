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

      unquote(html_helpers())
    end
  end

  def live_component do
    quote do
      use Phoenix.LiveComponent
      use Bilimbi.Base.UI.ActionFailureRecovery, :live_component

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
