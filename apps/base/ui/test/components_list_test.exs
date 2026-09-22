defmodule Bilimbi.Base.UI.ComponentsListTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Bilimbi.Base.UI.Components

  defp list_fixture(assigns) do
    ~H"""
    <.list id={@id}>
      <:item id="facts-name" title="Name">Acme Holdings</:item>
      <:item title="Status">Active</:item>
    </.list>
    """
  end

  test "renders each fact as a labelled row inside one definition list" do
    html = render_component(&list_fixture/1, id: "facts")

    assert html =~ ~r/<dl[^>]*\sid="facts"/
    assert html =~ ~s(<dt class="font-medium text-ink-subtle">Name</dt>)
    assert html =~ "Acme Holdings"
    assert html =~ ~s(<dt class="font-medium text-ink-subtle">Status</dt>)
    assert html =~ "Active"
  end

  test "a row carries its id only when the caller names one" do
    html = render_component(&list_fixture/1, id: "facts")

    assert html =~ ~s(id="facts-name")
    assert length(Regex.scan(~r/<div\s+id=/, html)) == 1
  end

  test "an unnamed list renders without an id attribute" do
    html = render_component(&list_fixture/1, id: nil)

    refute html =~ ~r/<dl[^>]*\sid=/
    assert html =~ ~r/<dl[^>]*\sclass="divide-y/
  end
end
