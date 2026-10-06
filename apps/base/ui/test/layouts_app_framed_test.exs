defmodule Bilimbi.Base.UI.LayoutsAppFramedTest do
  @moduledoc """
  `Layouts.app/1` renders chromeless when the scope is marked framed: the
  page's content, its flash, and the one element `<.datetime>` reads the
  clock from, and nothing a workspace tile would duplicate.
  """

  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias Bilimbi.Base.UI.Layouts

  defp page(assigns) do
    ~H"""
    <Layouts.app flash={%{}} current_scope={@current_scope} active_nav={nil}>
      <p id="page-body">Framed content</p>
    </Layouts.app>
    """
  end

  test "a framed scope gets only the content and the flash outlet" do
    html =
      render_component(&page/1, %{
        current_scope: %{framed: true, shell_preferences: %{mode: "local", theme: "system"}}
      })

    assert html =~ ~s(id="app-shell")
    assert html =~ ~s(data-framed="true")
    assert html =~ ~s(data-display-mode="local")
    assert html =~ ~s(id="app-content")
    assert html =~ ~s(id="page-body")
    assert html =~ ~s(id="flash-group")
    refute html =~ ~s(id="app-topbar")
    refute html =~ ~s(id="app-sidebar")
    refute html =~ ~s(id="app-statusbar")
  end

  # The stylesheet's "list fill" rules give a list page in a tile one
  # scrollbar, the table's. They start from these marks, so a component that
  # drops one silently returns the page to scrolling as a whole.
  test "a framed list page carries the marks the list fill rules read" do
    html =
      render_component(
        fn assigns ->
          ~H"""
          <Layouts.app flash={%{}} current_scope={@current_scope} active_nav={nil}>
            <Bilimbi.Base.UI.Components.page id="things-index">
              <Bilimbi.Base.UI.Components.header>Things</Bilimbi.Base.UI.Components.header>
              <Bilimbi.Base.UI.Components.card id="things-card" inner_class="p-0">
                <Bilimbi.Base.UI.Components.Lists.table
                  id="things"
                  rows={[%{name: "One"}]}
                  framed={false}
                >
                  <:col :let={thing} label="Name">{thing.name}</:col>
                </Bilimbi.Base.UI.Components.Lists.table>
              </Bilimbi.Base.UI.Components.card>
            </Bilimbi.Base.UI.Components.page>
          </Layouts.app>
          """
        end,
        %{current_scope: %{framed: true, shell_preferences: %{mode: "local", theme: "system"}}}
      )

    document = LazyHTML.from_fragment(html)

    # The tile's one scroll box is positioned, so an `sr-only` label inside
    # it cannot be laid out against the document and scroll that too.
    [main_class] =
      document
      |> LazyHTML.query("#app-shell[data-framed=true] > main#app-content")
      |> LazyHTML.attribute("class")

    assert "relative" in String.split(main_class)
    assert "overflow-y-auto" in String.split(main_class)

    chain =
      "#app-content > #things-index[data-page=list] > #things-card[data-card] > div > [data-table-region] > table"

    assert document |> LazyHTML.query(chain) |> Enum.count() == 1

    assert document |> LazyHTML.query("#things-index > header[data-page-header]") |> Enum.count() ==
             1
  end

  test "a shell scope renders its pin list, and a missing list is omitted" do
    loaded =
      render_component(&page/1, %{
        current_scope:
          shell_scope(%{pins: [%{id: 1, label: "Companies", url: "/companies", sort_order: 0}]})
      })

    assert loaded =~ ~s(data-pins=)
    assert loaded =~ "/companies"

    empty = render_component(&page/1, %{current_scope: shell_scope(%{pins: []})})
    assert empty =~ ~s(data-pins="[]")

    missing = render_component(&page/1, %{current_scope: shell_scope(%{})})
    refute missing =~ "data-pins"
  end

  defp shell_scope(extra) do
    Map.merge(
      %{
        user: %{
          "name" => "Ada Lovelace",
          "email" => "ada@example.com",
          "company_name" => "Bilimbi Industries"
        },
        scope: %{tenant: %{name: "Bilimbi", id: 41, is_platform_operator: false}},
        shell_preferences: %{
          mode: :local,
          modes: [:company, :local, :utc],
          theme: "system",
          timezone: "Etc/UTC"
        },
        impersonator: nil
      },
      extra
    )
  end
end
