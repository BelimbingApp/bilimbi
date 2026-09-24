defmodule Bilimbi.Base.UI.Web.DesignLibrarySpecimenController do
  @moduledoc """
  Receives the request the Design Library's submitting action-link specimen
  sends. It changes nothing and returns to the Components page, so trying
  the component on the reference page has no session or audit effect.
  """

  use Phoenix.Controller, formats: [:html]
  use Gettext, backend: Bilimbi.Base.UI.Gettext

  use Phoenix.VerifiedRoutes,
    router: Bilimbi.Base.UI.RouteContract,
    endpoint: Bilimbi.Base.UI.ScriptPath

  def create(conn, _params) do
    conn
    |> put_flash(:info, gettext("The action link sent its request. Nothing changed."))
    |> redirect(to: ~p"/system/design-library/components")
  end
end
