defmodule Bilimbi.Base.UI.ComponentsFilterToolbarTest do
  @moduledoc """
  The shared filter toolbar owns composition, not filtering.

  Two list toolbars broke their own alignment twice in one day because each
  page laid its controls out by its own rule: some labels visible and some
  hidden, helper text as a sibling paragraph with a hand-picked margin, and a
  grid that held native date inputs side by side past the viewport edge.
  These tests pin the rules that stop that drift: controls render where the
  caller wrote them, one shared field rule frames every control, every search
  box carries the same magnifier and the same typing contract, Enter filters
  in place, labels are screen-reader only, helper text sits below its control
  in one shape, and cells wrap.
  """

  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Bilimbi.Base.UI.Components

  defp toolbar(assigns) do
    ~H"""
    <.filter_toolbar id="tb-filters" form={@form} event="filters">
      <:control
        :if={@with_search}
        type={:search}
        field={@form[:search]}
        id="tb-search"
        label="Search things"
        placeholder="Search…"
      />
      <:control
        :if={@with_select}
        type={:select}
        field={@form[:status]}
        id="tb-status"
        label="Status filter"
        options={[{"All statuses", "all"}, {"Active", "active"}]}
      />
      <:control
        :if={@with_dates}
        type={:date}
        field={@form[:start_date]}
        id="tb-start-date"
        label="Start date"
        hint="UTC"
      />
      <:control
        :if={@with_dates}
        type={:date}
        field={@form[:end_date]}
        id="tb-end-date"
        label="End date"
        hint="UTC"
      />
      <:control
        :if={@with_trailing_select}
        type={:select}
        field={@form[:page_size]}
        id="tb-page-size"
        label="Rows per page"
        options={[{"25 / page", 25}, {"50 / page", 50}]}
      />
    </.filter_toolbar>
    """
  end

  defp form do
    to_form(
      %{
        "search" => "",
        "status" => "all",
        "start_date" => "",
        "end_date" => "",
        "page_size" => 25
      },
      as: :filters
    )
  end

  defp render_toolbar(opts \\ []) do
    render_component(&toolbar/1,
      form: form(),
      with_search: Keyword.get(opts, :with_search, true),
      with_select: Keyword.get(opts, :with_select, true),
      with_dates: Keyword.get(opts, :with_dates, true),
      with_trailing_select: Keyword.get(opts, :with_trailing_select, false)
    )
  end

  defp empty_toolbar(assigns) do
    ~H"""
    <.filter_toolbar id="tb-empty" form={@form} event="filters" />
    """
  end

  defp hinted_search(assigns) do
    ~H"""
    <.filter_toolbar id="tb-hinted" form={@form} event="filters">
      <:control
        type={:search}
        field={@form[:search]}
        id="tb-search"
        label="Search things"
        placeholder="Search…"
        hint="Matches name or code"
      />
    </.filter_toolbar>
    """
  end

  defp labels(html) do
    Regex.scan(~r/<label\b[^>]*>.*?<\/label>/s, html) |> Enum.map(&hd/1)
  end

  defp control_class(html, id) do
    [tag] = Regex.run(~r/<(?:input|select)\b[^>]*id="#{id}"[^>]*>/, html)

    tag
    |> String.split(~s(class="))
    |> Enum.at(1)
    |> String.split(~s("))
    |> hd()
    |> String.split()
  end

  defp search_box(html) do
    {relative_at, _} = :binary.match(html, ~s(<div class="relative">))
    rest = binary_part(html, relative_at, byte_size(html) - relative_at)
    [box] = Regex.run(~r|<div class="relative">.*?</div>\s*</div>|s, rest)
    box
  end

  test "every label stays accessible but takes no row height" do
    found = render_toolbar() |> labels()

    assert length(found) == 4

    for label <- found do
      assert label =~ "sr-only",
             "a visible label drops its control below its row-mates: #{label}"
    end
  end

  test "controls render in the order the caller declares them" do
    html = render_toolbar(with_trailing_select: true)

    order =
      ~w(tb-search tb-status tb-start-date tb-end-date tb-page-size)
      |> Enum.map(fn id ->
        {at, _} = :binary.match(html, ~s(id="#{id}"))
        {at, id}
      end)
      |> Enum.sort()
      |> Enum.map(&elem(&1, 1))

    assert order == ~w(tb-search tb-status tb-start-date tb-end-date tb-page-size),
           "grouping controls by type moves a page-size select into the middle of the date pair"
  end

  test "every control is framed by the one shared field rule" do
    html = render_toolbar(with_trailing_select: true)

    for id <- ~w(tb-search tb-status tb-start-date tb-end-date tb-page-size) do
      classes = control_class(html, id)

      assert "focus:border-brand-strong" in classes,
             "#{id} skips the shared brand-strong focus border"

      assert "focus:ring-brand-strong/30" in classes, "#{id} skips the shared focus ring"
      assert "shadow-xs" in classes, "#{id} skips the shared field elevation"
    end
  end

  test "a search box always shows the magnifier over the room that clears it" do
    html = render_toolbar()
    classes = control_class(html, "tb-search")

    assert search_box(html) =~ "hero-magnifying-glass",
           "the same leading icon on every list, or an operator meets a different search box per page"

    assert "pl-8" in classes,
           "the toolbar renders the leading icon, so the prompt text needs the clearance it takes"

    refute "px-3" in classes,
           "symmetric padding under a left-2.5 size-4 icon puts the prompt text under the magnifier"
  end

  test "every search box types on the same contract" do
    [tag] = Regex.run(~r/<input\b[^>]*id="tb-search"[^>]*>/, render_toolbar())

    assert tag =~ ~s(phx-debounce="300"),
           "one debounce, or two lists answer a keystroke differently"

    assert tag =~ ~s(maxlength="255"),
           "one length cap, or two lists stop accepting input at different points"

    assert tag =~ ~s(autocomplete="off"),
           "one autocomplete answer, or one list drops a saved-value menu over its filtered rows"
  end

  test "a search hint renders below the box the magnifier is centred in" do
    html = render_component(&hinted_search/1, form: form())
    box = search_box(html)

    assert html =~ "Matches name or code",
           "a hint the API accepts and never renders is helper text an operator never sees"

    assert box =~ "top-1/2" and box =~ "-translate-y-1/2",
           "the icon centres on its positioning box"

    refute box =~ "<label",
           "a label inside the box would drag the icon off the input's centre"

    refute box =~ "Matches name or code",
           "helper text inside the box would stretch it and drag the icon below the input"

    assert html =~ ~r|</div>\s*<p[^>]*>Matches name or code</p>|,
           "the hint follows the positioning box rather than sitting inside it"
  end

  test "date helper text rides each input's own hint" do
    html = render_toolbar()

    assert html =~ ~r/<input\b[^>]*id="tb-start-date"[^>]*>\s*<p[^>]*>UTC<\/p>/
    assert html =~ ~r/<input\b[^>]*id="tb-end-date"[^>]*>\s*<p[^>]*>UTC<\/p>/
    assert html |> String.split(">UTC</p>") |> length() == 3
  end

  test "cells wrap instead of holding a row wider than the viewport" do
    html = render_toolbar()

    assert html =~ "flex flex-wrap items-start",
           "the toolbar frames one wrapping row; a fixed side-by-side grid overflows narrow screens"

    refute html =~ "grid-cols-[",
           "column tracks with minimum widths are what pinned the date pair past the viewport edge"

    assert html =~
             ~r/<div[^>]*class="w-full min-w-0 sm:w-auto"[^>]*>\s*<label[^>]*for="tb-start-date"/s

    assert html =~
             ~r/<div[^>]*class="w-full min-w-0 sm:w-auto"[^>]*>\s*<label[^>]*for="tb-end-date"/s
  end

  test "filter state passes through untouched, and Enter filters in place" do
    html = render_toolbar()

    assert html =~ ~s(id="tb-filters")
    assert html =~ ~s(phx-change="filters")

    assert html =~ ~s(phx-submit="filters"),
           "without a submit binding Enter falls back to a native submit that reloads the page"

    assert html =~ ~s(name="filters[search]")
    assert html =~ ~s(name="filters[status]")
    assert html =~ ~s(name="filters[start_date]")
    assert html =~ ~s(name="filters[end_date]")
    assert html =~ ~s(id="tb-search")
    assert html =~ ~s(id="tb-status")
  end

  test "every control is optional and an empty toolbar is still a toolbar" do
    html = render_toolbar(with_search: false, with_dates: false)

    assert html =~ ~s(id="tb-status")
    refute html =~ ~s(id="tb-search")
    refute html =~ ~s(id="tb-start-date")

    empty = render_component(&empty_toolbar/1, form: form())

    assert empty =~ ~s(id="tb-empty")
    refute empty =~ "<input"
    refute empty =~ "<select"
  end
end
