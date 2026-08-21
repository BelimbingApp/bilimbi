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
    assert html =~ "border border-line-strong bg-surface text-ink hover:bg-surface-sunken"
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

  test "renders danger button with danger background and inverse ink" do
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
    assert html =~ "bg-danger text-ink-inverse hover:bg-danger-hover"
    assert html =~ "focus-visible:ring-danger/30"
    refute html =~ "bg-surface"
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

      ring_colors = Regex.scan(~r/focus-visible:ring-(?:action|danger)\/\d+/, html)
      assert length(ring_colors) == 1, "variant #{inspect(variant)}: #{inspect(ring_colors)}"
    end
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
