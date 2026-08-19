defmodule Bilimbi.Base.UI.ComponentsPaginationTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Bilimbi.Base.UI.Components

  defp pagination_fixture(assigns) do
    ~H"""
    <.pagination
      id="test-pagination"
      page={@page}
      page_sizes={@page_sizes}
      filters_form={to_form(%{"perPage" => @page.page_size}, as: :filters)}
    />
    """
  end

  test "renders standard pagination toolbar with summary, page size, and navigation buttons" do
    html =
      render_component(&pagination_fixture/1,
        page: %{page: 2, page_size: 25, total_pages: 5, total_entries: 120},
        page_sizes: [10, 25, 50, 100]
      )

    assert html =~ ~s(id="test-pagination")
    assert html =~ "Showing 26 to 50 of 120 results"
    assert html =~ ~s(id="test-pagination-page-size")
    assert html =~ ~s(id="test-pagination-previous")
    assert html =~ ~s(id="test-pagination-page-1")
    assert html =~ ~s(id="test-pagination-page-2")
    assert html =~ ~s(id="test-pagination-page-3")
    assert html =~ ~s(id="test-pagination-page-4")
    assert html =~ ~s(id="test-pagination-page-5")
    assert html =~ ~s(id="test-pagination-next")
  end

  test "highlights active page and marks aria-current" do
    html =
      render_component(&pagination_fixture/1,
        page: %{page: 2, page_size: 25, total_pages: 3, total_entries: 60},
        page_sizes: [10, 25, 50]
      )

    assert html =~
             ~s(id="test-pagination-page-2" type="button" phx-click="page" phx-value-page="2" aria-current="page")

    assert html =~ "border-brand-line bg-brand-surface text-brand-ink"
  end

  test "disables previous button on first page" do
    html =
      render_component(&pagination_fixture/1,
        page: %{page: 1, page_size: 25, total_pages: 3, total_entries: 60},
        page_sizes: [10, 25, 50]
      )

    assert html =~ ~s(id="test-pagination-previous")
    assert html =~ ~s(disabled)
  end

  test "disables next button on last page" do
    html =
      render_component(&pagination_fixture/1,
        page: %{page: 3, page_size: 25, total_pages: 3, total_entries: 60},
        page_sizes: [10, 25, 50]
      )

    assert html =~ ~s(id="test-pagination-next")
    assert html =~ ~s(disabled)
  end

  test "renders ellipsis when pages have gaps" do
    html =
      render_component(&pagination_fixture/1,
        page: %{page: 10, page_size: 10, total_pages: 20, total_entries: 200},
        page_sizes: [10, 25, 50]
      )

    assert html =~ "…"
    assert html =~ ~s(id="test-pagination-page-1")
    assert html =~ ~s(id="test-pagination-page-10")
    assert html =~ ~s(id="test-pagination-page-20")
  end

  test "renders summary count and page size selector on a single page, but hides page navigation buttons" do
    html =
      render_component(&pagination_fixture/1,
        page: %{page: 1, page_size: 25, total_pages: 1, total_entries: 2},
        page_sizes: [25, 50, 100, 300]
      )

    assert html =~ ~s(id="test-pagination")
    assert html =~ ~s(id="test-pagination-summary")
    assert html =~ "Showing 1 to 2 of 2 results"
    assert html =~ ~s(id="test-pagination-page-size")
    refute html =~ ~s(id="test-pagination-previous")
    refute html =~ ~s(id="test-pagination-page-1")
    refute html =~ ~s(id="test-pagination-next")
  end

  test "renders page size selector on empty results, but hides summary count and page navigation buttons" do
    html =
      render_component(&pagination_fixture/1,
        page: %{page: 1, page_size: 25, total_pages: 0, total_entries: 0},
        page_sizes: [25, 50, 100, 300]
      )

    assert html =~ ~s(id="test-pagination")
    refute html =~ ~s(id="test-pagination-summary")
    assert html =~ ~s(id="test-pagination-page-size")
    refute html =~ ~s(id="test-pagination-previous")
    refute html =~ ~s(id="test-pagination-page-1")
    refute html =~ ~s(id="test-pagination-next")
  end
end
