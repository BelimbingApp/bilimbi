defmodule Bilimbi.Base.UI.ComponentsConnectionBannersTest do
  @moduledoc """
  `connection_banners/1` renders the pair the client reveals when the
  websocket drops, and the seam through which one outlet stands down for
  another: every banner is marked `data-connection-banners`, and a pair that
  `yields` also carries `data-yields`, which `app.css` keeps invisible while
  any other pair is in the document.

  What is asserted here is the markup contract the stylesheet keys on. That
  the yielding pair then stays out of sight is browser-only and is proven in
  `BilimbiWeb.ConnectionBannersCssTest` on the stylesheet side.
  """

  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  defp render_pair(assigns) do
    render_component(
      fn assigns ->
        ~H"""
        <Bilimbi.Base.UI.Components.connection_banners id={@id} yields={@yields} />
        """
      end,
      Map.merge(%{id: "pair", yields: false}, assigns)
    )
  end

  defp tag(html, id) do
    assert [tag] = Regex.run(~r/<div[^>]*\sid="#{id}"[^>]*>/, html),
           "no element with id #{id} rendered"

    tag
  end

  test "both banners derive their ids from the outlet and start hidden" do
    html = render_pair(%{id: "attach-modal"})

    for id <- ["attach-modal-client-error", "attach-modal-server-error"] do
      tag = tag(html, id)
      assert tag =~ ~s(role="alert")
      assert tag =~ ~r/\shidden[\s>]/
    end
  end

  test "every banner is marked as a connection outlet, and only a yielding pair yields" do
    reporting = render_pair(%{id: "reporting"})
    yielding = render_pair(%{id: "yielding", yields: true})

    for kind <- ~w(client server) do
      assert tag(reporting, "reporting-#{kind}-error") =~ ~r/\sdata-connection-banners[\s>]/
      refute tag(reporting, "reporting-#{kind}-error") =~ "data-yields"

      assert tag(yielding, "yielding-#{kind}-error") =~ ~r/\sdata-connection-banners[\s>]/
      assert tag(yielding, "yielding-#{kind}-error") =~ ~r/\sdata-yields[\s>]/
    end
  end
end
