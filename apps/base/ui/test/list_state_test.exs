defmodule Bilimbi.Base.UI.ListStateTest do
  use ExUnit.Case, async: true

  alias Bilimbi.Base.UI.ListState

  setup do
    spec =
      ListState.spec!(
        sortable: %{name: :asc, created_at: :desc},
        default_sort: :name,
        page_sizes: [25, 50, 100],
        default_page_size: 25,
        page_size_param: "per_page",
        filters: [result: {:one_of, ~w(allowed denied), ""}]
      )

    {:ok, spec: spec}
  end

  test "a forged query falls back instead of raising", %{spec: spec} do
    state =
      ListState.parse(
        %{
          "sort_by" => "drop_table",
          "sort_dir" => "sideways",
          "page" => "x",
          "per_page" => "nope",
          "result" => "maybe"
        },
        spec
      )

    assert state.search == ""
    assert state.page == 1
    assert state.page_size == 25
    assert state.sort_by == :name
    assert state.sort_dir == :asc
    assert state.filters.result == ""
  end

  test "a missing sort direction uses the column default", %{spec: spec} do
    state = ListState.parse(%{"sort_by" => "created_at"}, spec)
    assert state.sort_by == :created_at
    assert state.sort_dir == :desc

    explicit = ListState.parse(%{"sort_by" => "created_at", "sort_dir" => "asc"}, spec)
    assert explicit.sort_dir == :asc
  end

  test "whitespace around a page size is a page size", %{spec: spec} do
    state = ListState.parse(%{"per_page" => " 50 "}, spec)
    assert state.page_size == 50
  end

  test "the query key is the one the spec names", %{spec: spec} do
    state = ListState.parse(%{"page_size" => "50", "per_page" => "100"}, spec)
    assert state.page_size == 100

    params = state |> ListState.put_page("2") |> ListState.to_params()
    assert params["per_page"] == 100
    assert params["page"] == 2
    refute Map.has_key?(params, "page_size")
  end

  test "an alias supplies the page size only when the query key is absent" do
    spec =
      ListState.spec!(
        page_sizes: [25, 50],
        default_page_size: 25,
        page_size_param: "page_size",
        page_size_aliases: ["perPage"],
        omit_blank: [:search]
      )

    assert ListState.parse(%{"perPage" => "50"}, spec).page_size == 50
    assert ListState.parse(%{"page_size" => "25", "perPage" => "50"}, spec).page_size == 25

    params = ListState.parse(%{}, spec) |> ListState.to_params()
    assert params == %{"page" => 1, "page_size" => 25}
  end

  test "a header click takes the column default, then flips", %{spec: spec} do
    state = ListState.parse(%{}, spec)

    opened = ListState.next_sort(state, "created_at")
    assert opened.sort_by == :created_at
    assert opened.sort_dir == :desc
    assert opened.page == 1

    flipped = ListState.next_sort(opened, "created_at")
    assert flipped.sort_dir == :asc

    assert ListState.next_sort(state, "drop_table") == state
    assert ListState.next_sort(state, nil) == state
  end

  test "a posted filter keeps keys the form did not send and resets the page", %{spec: spec} do
    state = ListState.parse(%{"search" => "ada", "result" => "denied", "page" => "4"}, spec)

    next = ListState.apply_filters(state, %{"perPage" => "50"})
    assert next.search == "ada"
    assert next.filters.result == "denied"
    assert next.page_size == 50
    assert next.page == 1
  end

  test "an unrecognised posted page size keeps the current size, or the default when asked",
       %{spec: spec} do
    state = ListState.parse(%{"per_page" => "50"}, spec)

    assert ListState.apply_filters(state, %{"perPage" => "999"}).page_size == 50
    assert ListState.apply_filters(state, %{}).page_size == 50

    resetting =
      ListState.spec!(
        sortable: %{name: :asc},
        default_sort: :name,
        page_sizes: [25, 50],
        default_page_size: 25,
        page_size_param: "page_size",
        invalid_page_size: :default
      )

    current = ListState.parse(%{"page_size" => "50"}, resetting)
    assert ListState.apply_filters(current, %{"perPage" => "999"}).page_size == 25
    assert ListState.apply_filters(current, %{}).page_size == 50
  end

  test "blank keys stay in the query unless the spec omits them", %{spec: spec} do
    params = ListState.parse(%{}, spec) |> ListState.to_params()
    assert params["search"] == ""
    assert params["result"] == ""
    assert params["sort_by"] == "name"
    assert params["sort_dir"] == "asc"
  end

  test "clamp lands on the last page and leaves an empty result unless asked" do
    spec = ListState.spec!(page_sizes: [25], default_page_size: 25)
    state = ListState.parse(%{"page" => "9"}, spec)

    assert ListState.clamp_to_last_page(state, %{total_pages: 2}).page == 2
    assert ListState.clamp_to_last_page(state, %{total_pages: 0}).page == 9
    assert ListState.clamp_to_last_page(state, %{total_pages: 0}, empty: :reset).page == 1
    assert ListState.clamp_to_last_page(state, %{total_pages: 9}).page == 9
  end

  test "the toolbar form posts perPage and the extra filters", %{spec: spec} do
    state = ListState.parse(%{"search" => "ada", "result" => "allowed", "per_page" => "50"}, spec)
    form = ListState.filters_form(state)

    assert form[:search].value == "ada"
    assert form[:result].value == "allowed"
    assert form[:perPage].value == "50"
    assert form.name == "filters"
  end

  test "a string filter can rewrite one value and omit a blank" do
    spec =
      ListState.spec!(
        page_sizes: [25],
        default_page_size: 25,
        omit_blank: [:source],
        filters: [source: {:string, "", %{"all" => ""}}]
      )

    assert ListState.parse(%{"source" => "all"}, spec).filters.source == ""
    assert ListState.parse(%{"source" => "base/authz"}, spec).filters.source == "base/authz"

    state = ListState.parse(%{"source" => "base/authz"}, spec)
    assert ListState.to_params(state)["source"] == "base/authz"

    posted = ListState.apply_filters(state, %{"source" => "all"})
    assert posted.filters.source == ""
    refute Map.has_key?(ListState.to_params(posted), "source")
  end

  test "spec! rejects a default sort or page size outside the allowed set" do
    assert_raise ArgumentError, ~r/default_sort/, fn ->
      ListState.spec!(
        sortable: %{name: :asc},
        default_sort: :code,
        page_sizes: [25],
        default_page_size: 25
      )
    end

    assert_raise ArgumentError, ~r/default_page_size/, fn ->
      ListState.spec!(page_sizes: [25], default_page_size: 10)
    end

    assert_raise ArgumentError, ~r/page_sizes is required/, fn ->
      ListState.spec!([])
    end
  end

  describe "a list that shares its URL with another" do
    setup do
      spec =
        ListState.spec!(
          sortable: %{name: :asc, email: :asc},
          default_sort: :name,
          page_sizes: [25, 50],
          default_page_size: 25,
          page_size_param: "per_page",
          page_size_aliases: ["perPage"],
          invalid_page_size: :default,
          param_prefix: "users_",
          param_names: %{sort_by: "sort", sort_dir: "dir"},
          omit_defaults: true
        )

      {:ok, prefixed: spec}
    end

    test "parses and writes prefixed keys, leaving other lists' keys alone", %{prefixed: spec} do
      params = %{
        "users_search" => "ada",
        "users_sort" => "email",
        "users_dir" => "desc",
        "users_page" => "3",
        "users_perPage" => "50",
        "page" => "9",
        "sort" => "name"
      }

      state = ListState.parse(params, spec)

      assert %{search: "ada", sort_by: :email, sort_dir: :desc, page: 3, page_size: 50} = state

      assert ListState.to_params(state) == %{
               "users_search" => "ada",
               "users_sort" => "email",
               "users_dir" => "desc",
               "users_page" => 3,
               "users_per_page" => 50
             }
    end

    test "omits every default so the URL stays short", %{prefixed: spec} do
      assert ListState.to_params(ListState.parse(%{}, spec)) == %{}

      state = ListState.parse(%{"users_sort" => "email"}, spec)
      assert ListState.to_params(state) == %{"users_sort" => "email"}
    end

    test "names the toolbar form", %{prefixed: spec} do
      form = ListState.filters_form(ListState.parse(%{}, spec), as: :users_filters)
      assert form.name == "users_filters"
    end
  end

  describe "paginate/2" do
    test "slices the rows and clamps a page past the end", %{spec: spec} do
      rows = Enum.to_list(1..60)
      state = ListState.parse(%{"page" => "2", "per_page" => "25"}, spec)

      page = ListState.paginate(rows, state)
      assert page.entries == Enum.to_list(26..50)
      assert %{total_entries: 60, total_pages: 3, has_prev?: true, has_next?: true} = page

      clamped = ListState.paginate(rows, %{state | page: 99})
      assert clamped.page == 3
      assert clamped.entries == Enum.to_list(51..60)
      refute clamped.has_next?
    end

    test "no rows is page 1 of zero pages", %{spec: spec} do
      page = ListState.paginate([], ListState.parse(%{"page" => "4"}, spec))

      assert %{entries: [], page: 1, total_entries: 0, total_pages: 0} = page
      refute page.has_prev?
      refute page.has_next?
    end
  end
end
