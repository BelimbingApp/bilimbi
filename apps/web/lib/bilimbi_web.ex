defmodule BilimbiWeb do
  @moduledoc """
  The entrypoint for defining the host web interface, such
  as controllers and the router.

  LiveViews use `Bilimbi.Base.UI, :live_view`. There is one Gettext
  backend, `Bilimbi.Base.UI.Gettext`.

  This can be used in your application as:

      use BilimbiWeb, :controller

  The definitions below will be executed for every controller
  and the router, so keep them short and clean, focused
  on imports, uses and aliases.

  Do NOT define functions inside the quoted expressions
  below. Instead, define additional modules and import
  those modules here.
  """

  def static_paths, do: ~w(assets fonts images favicon.ico favicon.svg robots.txt)

  def router do
    quote do
      use Phoenix.Router, helpers: false

      # Import common connection and controller functions to use in pipelines
      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def controller do
    quote do
      use Phoenix.Controller, formats: [:html, :json]

      use Gettext, backend: Bilimbi.Base.UI.Gettext

      import Plug.Conn

      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: BilimbiWeb.Endpoint,
        router: BilimbiWeb.Router,
        statics: BilimbiWeb.static_paths()
    end
  end

  @doc """
  When used, dispatch to the appropriate controller or router.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
