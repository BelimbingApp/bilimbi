defmodule Bilimbi.Base.UI.ComponentsConnectionBannersTest do
  @moduledoc """
  `connection_banners/1` renders the pair the client reveals when the
  websocket drops. `revealed` renders one banner already shown and bound to
  no connection event, so presenting it never adds a second live outlet.
  """

  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  defp render_pair(assigns) do
    render_component(
      fn assigns ->
        ~H"""
        <Bilimbi.Base.UI.Components.connection_banners id={@id} {@extra} />
        """
      end,
      Map.merge(%{id: "pair", extra: %{}}, assigns)
    )
  end

  defp tags(html) do
    Regex.scan(~r/<div[^>]*\sid="([^"]+-error)"[^>]*>/, html)
    |> Map.new(fn [tag, id] -> {id, tag} end)
  end

  test "a live pair derives its ids from the container, starts hidden and follows the connection" do
    tags = tags(render_pair(%{id: "attach-modal"}))

    assert Map.keys(tags) == ["attach-modal-client-error", "attach-modal-server-error"]

    for {_id, tag} <- tags do
      assert tag =~ ~s(role="alert")
      assert tag =~ ~r/\shidden[\s>]/
      assert tag =~ "phx-disconnected="
      assert tag =~ "phx-connected="
    end
  end

  for kind <- [:client, :server] do
    test "revealed #{kind} renders only that banner, shown and bound to no connection event" do
      tags = tags(render_pair(%{id: "specimen", extra: %{revealed: unquote(kind)}}))

      id = "specimen-#{unquote(kind)}-error"
      assert [{^id, tag}] = Map.to_list(tags)
      assert tag =~ ~s(role="alert")
      refute tag =~ ~r/\shidden[\s>=]/
      refute tag =~ "phx-disconnected"
      refute tag =~ "phx-connected"
    end
  end
end
