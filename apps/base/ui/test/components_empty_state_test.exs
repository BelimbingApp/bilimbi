defmodule Bilimbi.Base.UI.ComponentsEmptyStateTest do
  @moduledoc """
  An empty region has to tell the person what is missing, why, and what they
  can do about it, and a region they may not see has to say so instead of
  looking empty. These lock the words and the reachability from the table,
  not the styling.
  """

  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Bilimbi.Base.UI.Components

  # The visible words, in order, with markup and whitespace collapsed, so the
  # assertions read the copy a person reads rather than class strings.
  defp text(html) do
    html
    |> String.replace(~r/<[^>]+>/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp first_run(assigns) do
    ~H"""
    <.empty_state
      id="companies-empty"
      title="No companies yet"
      reason="Companies you create appear here."
    >
      <:action>
        <.button id="companies-empty-add" navigate="/companies/create">Add Company</.button>
      </:action>
    </.empty_state>
    """
  end

  defp filtered(assigns) do
    ~H"""
    <.empty_state
      title="No companies match “acme”"
      reason="Clear the search to see every company."
    >
      <:action>
        <.button id="companies-clear-search" patch="/companies">Clear search</.button>
      </:action>
    </.empty_state>
    """
  end

  test "says what is missing, why, and offers the recovery" do
    html = render_component(&first_run/1, %{})

    assert text(html) =~ "No companies yet"
    assert text(html) =~ "Companies you create appear here."
    assert html =~ ~s(id="companies-empty-add")
    assert html =~ ~s(href="/companies/create")
  end

  test "first-run and no-match are different sentences with different recoveries" do
    first_run = text(render_component(&first_run/1, %{}))
    filtered = text(render_component(&filtered/1, %{}))

    refute first_run =~ "match"
    assert filtered =~ "No companies match “acme”"
    assert filtered =~ "Clear search"
    refute filtered =~ "Add Company"
  end

  test "reason and recovery are optional" do
    html = render_component(&empty_state/1, %{title: "No roles assigned", action: []})

    assert text(html) == "No roles assigned"
  end

  test "a forbidden region uses the one permission wording and names the recovery" do
    html = render_component(&empty_state/1, %{forbidden: "view companies", action: []})

    assert text(html) ==
             "You do not have permission to view companies. Ask an operator to review your role."

    refute text(html) =~ ~r/try again/i
    refute text(html) =~ ~r/\bno companies\b/i
  end

  test "refuses a call that says both what is missing and what is forbidden" do
    assert_raise ArgumentError, ~r/not both/, fn ->
      render_component(&empty_state/1, %{
        title: "No companies yet",
        forbidden: "create companies",
        action: []
      })
    end
  end

  test "refuses a call that says neither what is missing nor what is forbidden" do
    assert_raise ArgumentError, ~r/needs a title/, fn ->
      render_component(&empty_state/1, %{action: []})
    end
  end

  describe "from the table's empty slot" do
    defp people_table(assigns) do
      ~H"""
      <.table id="people" rows={[]}>
        <:col :let={row} label="Name">{row.name}</:col>
        <:empty :if={@empty == :plain}>Nobody here.</:empty>
        <:empty
          :if={@empty == :filtered}
          title="No people match “ada”"
          reason="Clear the search to see everyone."
        >
          <.button id="people-clear-search" patch="/people">Clear search</.button>
        </:empty>
        <:empty :if={@empty == :forbidden} forbidden="view people" />
      </.table>
      """
    end

    test "plain content still renders as given" do
      html = render_component(&people_table/1, %{empty: :plain})

      assert html =~ ~s(id="people-empty")
      assert text(html) =~ "Nobody here."
    end

    test "title and reason render the pattern with the slot body as the recovery" do
      html = render_component(&people_table/1, %{empty: :filtered})

      assert html =~ ~s(id="people-empty")
      assert text(html) =~ "No people match “ada” Clear the search to see everyone. Clear search"
      assert html =~ ~s(id="people-clear-search")
    end

    test "a forbidden table row uses the permission wording without an empty recovery block" do
      html = render_component(&people_table/1, %{empty: :forbidden})

      assert text(html) =~
               "You do not have permission to view people. Ask an operator to review your role."

      refute html =~ "mt-3"
    end
  end
end
