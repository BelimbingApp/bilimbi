defmodule Bilimbi.Base.UI.ComponentsPageTest do
  @moduledoc """
  Tests for the `<.page>` container: the one place a screen's content width
  is chosen (#287).
  """

  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Bilimbi.Base.UI.Components

  defp render_page(assigns \\ %{}, variant \\ nil) do
    render_component(
      fn assigns ->
        ~H"""
        <%= if @variant do %>
          <.page id="p" variant={@variant}>content</.page>
        <% else %>
          <.page id="p">content</.page>
        <% end %>
        """
      end,
      %{variant: variant}
    )
  end

  test "list is the default and the widest" do
    assert render_page() =~ ~s(class="mx-auto max-w-7xl")
    assert render_page(%{}, :list) =~ "max-w-7xl"
  end

  test "form and detail have their own widths" do
    assert render_page(%{}, :form) =~ "max-w-2xl"
    assert render_page(%{}, :detail) =~ "max-w-4xl"
  end

  test "id, extra classes and global attributes pass through" do
    html =
      render_component(
        fn assigns ->
          ~H"""
          <.page id="users-index" class="space-y-5" data-role="index">content</.page>
          """
        end,
        %{}
      )

    assert html =~ ~s(id="users-index")
    assert html =~ "space-y-5"
    assert html =~ ~s(data-role="index")
    assert html =~ "content"
  end
end
