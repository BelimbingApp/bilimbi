defmodule Bilimbi.Base.UI.ComponentsButtonTest do
  @moduledoc """
  Tests for the `<.button>` component variants and attributes.
  """

  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Bilimbi.Base.UI.Components

  test "renders default button with bordered surface classes" do
    html =
      render_component(
        fn assigns ->
          ~H"""
          <.button id="default-btn">Save</.button>
          """
        end,
        %{}
      )

    assert html =~ ~s(id="default-btn")
    assert html =~ "border border-high-contrast-line bg-surface text-ink hover:bg-surface-sunken"
    assert html =~ "Save"
  end

  test "renders primary button with action background and ink" do
    html =
      render_component(
        fn assigns ->
          ~H"""
          <.button id="primary-btn" variant="primary">Create</.button>
          """
        end,
        %{}
      )

    assert html =~ ~s(id="primary-btn")
    assert html =~ "bg-action text-action-ink hover:bg-action-hover"
    refute html =~ "bg-brand"
  end

  test "renders danger button as a calm text action" do
    html =
      render_component(
        fn assigns ->
          ~H"""
          <.button id="danger-btn" variant="danger">Delete</.button>
          """
        end,
        %{}
      )

    assert html =~ ~s(id="danger-btn")
    assert html =~ "text-danger hover:bg-danger-surface"
    assert html =~ "hover:underline"
    assert html =~ "focus-visible:ring-brand-strong/30"
    refute html =~ "bg-danger text-ink-inverse"
    refute html =~ "shadow-sm"
  end

  test "each variant defines the focus ring color exactly once" do
    for variant <- [nil, "primary", "danger"] do
      html =
        render_component(
          fn assigns ->
            ~H"""
            <.button id="ring-btn" variant={@variant}>Act</.button>
            """
          end,
          %{variant: variant}
        )

      ring_colors = Regex.scan(~r/focus-visible:ring-brand-strong\/\d+/, html)
      assert length(ring_colors) == 1, "variant #{inspect(variant)}: #{inspect(ring_colors)}"
    end
  end

  test "icon buttons use context size and keep their accessible label" do
    inline =
      render_component(
        fn assigns ->
          ~H"""
          <.icon_button
            id="pin-btn"
            icon="bilimbi-pin"
            label="Pin page"
            context={:inline}
          />
          """
        end,
        %{}
      )

    table =
      render_component(
        fn assigns ->
          ~H"""
          <.icon_button id="delete-btn" icon="hero-trash" label="Delete row" kind={:danger} />
          """
        end,
        %{}
      )

    assert inline =~ ~s(aria-label="Pin page")
    assert inline =~ ~s(title="Pin page")
    assert inline =~ "size-5 rounded-sm"
    assert inline =~ "size-3.5"

    assert table =~ "size-7 rounded-md"
    assert table =~ "size-4"
    assert table =~ "text-danger hover:bg-danger-surface"
  end

  test "caller-supplied class extends variant styling" do
    html =
      render_component(
        fn assigns ->
          ~H"""
          <.button id="extended-btn" variant="primary" class="w-full custom-class">Submit</.button>
          """
        end,
        %{}
      )

    assert html =~ "bg-action text-action-ink hover:bg-action-hover"
    assert html =~ "w-full custom-class"
  end

  test "renders link button when navigate or href is supplied" do
    html =
      render_component(
        fn assigns ->
          ~H"""
          <.button id="nav-btn" navigate="/users">Go to Users</.button>
          """
        end,
        %{}
      )

    assert html =~ ~s(<a)
    assert html =~ ~s(href="/users")
    assert html =~ "Go to Users"
  end
end
