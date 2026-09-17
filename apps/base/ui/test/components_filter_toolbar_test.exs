defmodule Bilimbi.Base.UI.ComponentsFilterToolbarTest do
  @moduledoc """
  The shared filter toolbar owns composition, not filtering.

  Two list toolbars broke their own alignment twice in one day because each
  page laid its controls out by its own rule: some labels visible and some
  hidden, helper text as a sibling paragraph with a hand-picked margin, and a
  grid that held native date inputs side by side past the viewport edge.
  These tests pin the three rules that stop that drift: labels all visible or
  all hidden, hints through the input component, and cells that wrap.
  """

  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Bilimbi.Base.UI.Components

  alias Bilimbi.Base.UI.Components

  defp toolbar(assigns) do
    ~H"""
    <.filter_toolbar
      id="tb-filters"
      form={@form}
      event="filters"
      submit_event={@submit_event}
      labels={@labels}
    >
      <:search
        :if={@with_search}
        field={@form[:search]}
        id="tb-search"
        label="Search things"
        placeholder="Search…"
        icon="search"
        debounce="300"
        maxlength="255"
      />
      <:select
        :if={@with_select}
        field={@form[:status]}
        id="tb-status"
        label="Status filter"
        options={[{"All statuses", "all"}, {"Active", "active"}]}
      />
      <:date_range
        :if={@with_dates}
        from_id="tb-start-date"
        from_field={@form[:start_date]}
        from_label="Start date (UTC)"
        to_id="tb-end-date"
        to_field={@form[:end_date]}
        to_label="End date (UTC)"
        hint="UTC"
      />
    </.filter_toolbar>
    """
  end

  defp form do
    to_form(
      %{"search" => "", "status" => "all", "start_date" => "", "end_date" => ""},
      as: :filters
    )
  end

  defp render_toolbar(opts \\ []) do
    render_component(&toolbar/1,
      form: form(),
      labels: Keyword.get(opts, :labels, :hidden),
      submit_event: Keyword.get(opts, :submit_event, nil),
      with_search: Keyword.get(opts, :with_search, true),
      with_select: Keyword.get(opts, :with_select, true),
      with_dates: Keyword.get(opts, :with_dates, true)
    )
  end

  defp empty_toolbar(assigns) do
    ~H"""
    <.filter_toolbar id="tb-empty" form={@form} event="filters" />
    """
  end

  defp labels(html) do
    Regex.scan(~r/<label\b[^>]*>.*?<\/label>/s, html) |> Enum.map(&hd/1)
  end

  test "hidden labels stay accessible but take no row height" do
    found = render_toolbar() |> labels()

    assert length(found) == 4

    for label <- found do
      assert label =~ "sr-only",
             "every toolbar label hides together, or the labelled controls drop a row: #{label}"
    end
  end

  test "visible labels share one shape on every control" do
    found = render_toolbar(labels: :visible) |> labels()

    assert length(found) == 4
    refute Enum.any?(found, &(&1 =~ "sr-only"))

    for label <- found do
      assert label =~ "mb-1.5 block text-sm font-medium text-ink",
             "a label with its own spacing breaks the shared row: #{label}"
    end
  end

  test "the toolbar label mirrors the input label it stands in for" do
    input_html =
      render_component(
        &field/1,
        id: "mirror",
        name: "mirror",
        value: "",
        type: "text",
        label: "Same label"
      )

    [input_label] = labels(input_html)
    [toolbar_label | _] = render_toolbar(labels: :visible) |> labels()

    class_tokens = fn label ->
      label |> String.split(~s(class=")) |> Enum.at(1) |> String.split(~s(")) |> hd() |> String.split()
    end

    assert class_tokens.(toolbar_label) == class_tokens.(input_label),
           "the toolbar renders labels itself, so a change to the input label must land here too"
  end

  defp field(assigns) do
    ~H"""
    <.input
      id={@id}
      name={@name}
      value={@value}
      type={@type}
      label={@label}
      errors={[]}
    />
    """
  end

  test "the API offers no per-control label or wrapper override" do
    %{slots: slots} = Components.__components__()[:filter_toolbar]

    overridden =
      for slot <- slots,
          %{name: attr} <- slot.attrs,
          attr in [:label_class, :wrapper_class],
          do: "#{slot.name}.#{attr}"

    assert overridden == [],
           "a per-control label or wrapper class is how mixed visibility and bespoke spacing return: #{inspect(overridden)}"
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

    assert html =~ ~r/<div[^>]*class="w-full min-w-0 sm:w-auto"[^>]*>\s*<label[^>]*for="tb-start-date"/s
    assert html =~ ~r/<div[^>]*class="w-full min-w-0 sm:w-auto"[^>]*>\s*<label[^>]*for="tb-end-date"/s
  end

  test "the search icon centers on the input, above or below a label alike" do
    for labels <- [:hidden, :visible] do
      html = render_toolbar(labels: labels)

      {relative_at, _} = :binary.match(html, ~s(<div class="relative">))
      {input_at, _} = :binary.match(html, ~s(id="tb-search"))
      box = binary_part(html, relative_at, input_at - relative_at)

      assert box =~ "top-1/2" and box =~ "-translate-y-1/2",
             "the icon lives in the relative box around the input (#{labels} labels)"

      refute box =~ "<label",
             "a label inside the relative box would drag the icon off the input's center (#{labels} labels)"
    end
  end

  test "filter state passes through untouched" do
    html = render_toolbar(submit_event: "filters")

    assert html =~ ~s(id="tb-filters")
    assert html =~ ~s(phx-change="filters")
    assert html =~ ~s(phx-submit="filters")
    assert html =~ ~s(name="filters[search]")
    assert html =~ ~s(name="filters[status]")
    assert html =~ ~s(name="filters[start_date]")
    assert html =~ ~s(name="filters[end_date]")
    assert html =~ ~s(id="tb-search")
    assert html =~ ~s(id="tb-status")
  end

  test "every slot is optional, but an empty toolbar raises" do
    html = render_toolbar(with_search: false, with_dates: false)

    assert html =~ ~s(id="tb-status")
    refute html =~ ~s(id="tb-search")
    refute html =~ ~s(id="tb-start-date")

    assert_raise ArgumentError, ~r/at least one control/, fn ->
      render_component(&empty_toolbar/1, form: form())
    end
  end
end
