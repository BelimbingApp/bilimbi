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

  @doc """
  The signed-in user's id, from the `current_scope` assign.

  `BilimbiWeb.UserAuth.presentation_user/2` is the only thing that builds this
  map, and it always writes a positive integer under `"user_id"`. So there is
  one shape, and anything else means scope propagation is broken — a route
  without the right `live_session`, or a component rendered outside it.

  This raises rather than returning a default on purpose. Three adapters
  previously fell back to user id `0`, which scoped every read to a user that
  does not exist: empty lists and a working-looking screen instead of a crash
  naming the bug. AGENTS.md §9 is explicit that a missing assign is fixed at
  the route, not papered over with a value.
  """
  @spec current_user_id(map()) :: pos_integer()
  def current_user_id(%{user: %{"user_id" => id}}) when is_integer(id) and id > 0, do: id

  def current_user_id(current_scope) do
    raise ArgumentError,
          "current_scope carries no \"user_id\"; fix the route's live_session and " <>
            "scope propagation rather than defaulting the id. Got: #{inspect(current_scope)}"
  end

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
      import Bilimbi.Base.UI, only: [allowed?: 2, current_user_id: 1]
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
