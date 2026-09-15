defmodule BilimbiWeb.SidebarRailScopeTest do
  @moduledoc """
  Rail is a state of the sidebar, not of the shell.

  `Layouts.nav_branch/1` rows carry `.app-nav-*` classes wherever they render,
  and the Design Library renders the shell's real rail outside `#app-sidebar`.
  While the rail rules in `app.css` were keyed to `#app-shell` alone they also
  matched those rows, so collapsing the sidebar to rail hid the Design Library
  Navigation card's labels and carets and left three bare icons under prose
  describing rows that were no longer visible.

  These run the rail rules as selectors against the real rendered page, so a
  rule that escapes the sidebar fails here rather than in a reviewer's browser.
  """

  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  @css_path Path.expand("../assets/css/app.css", __DIR__)

  # The AppShell hook writes this attribute from the saved rail preference; a
  # reviewer can land on any page with it already set.
  @rail_attr ~s([data-sidebar-rail="true"])

  # The Design Library Components page is the one shipped screen that renders
  # nav rows outside the sidebar.
  @page "/system/design-library/components"
  @view_cap "admin.system.design-library.view"

  setup do
    UserFixtures.create_user_tables!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})
    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})

    %{rail_selectors: rail_selectors()}
  end

  defp open(conn) do
    grant_capabilities!(@view_cap)
    {:ok, _view, html} = conn |> log_in_as() |> live(@page)
    html
  end

  # Every selector in `app.css` that only applies while the sidebar is railed.
  # Innermost blocks only, so `@media` headers are skipped.
  defp rail_selectors do
    css = @css_path |> File.read!() |> String.replace(~r|/\*.*?\*/|s, "")

    for [_, selector_list, _declarations] <- Regex.scan(~r/([^{}]+)\{([^{}]*)\}/, css),
        selector <- String.split(selector_list, ","),
        selector = String.trim(selector),
        String.contains?(selector, @rail_attr),
        do: selector
  end

  # The page as a railed shell, and the same shell with the sidebar cut out.
  # A rail rule that matches anything in the second one has escaped.
  defp railed_documents(html) do
    tree = html |> LazyHTML.from_document() |> LazyHTML.to_tree()
    railed = map_tree(tree, &rail_on/1)

    {LazyHTML.from_tree(railed), LazyHTML.from_tree(map_tree(railed, &drop_sidebar/1))}
  end

  defp map_tree(nodes, fun) when is_list(nodes) do
    nodes
    |> Enum.map(fn node -> node |> fun.() |> map_children(fun) end)
    |> Enum.reject(&is_nil/1)
  end

  defp map_children({tag, attrs, children}, fun), do: {tag, attrs, map_tree(children, fun)}
  defp map_children(node, _fun), do: node

  defp rail_on({tag, attrs, children}) do
    if id(attrs) == "app-shell" do
      {tag, List.keystore(attrs, "data-sidebar-rail", 0, {"data-sidebar-rail", "true"}), children}
    else
      {tag, attrs, children}
    end
  end

  defp rail_on(node), do: node

  defp drop_sidebar({_tag, attrs, _children} = node) do
    if id(attrs) == "app-sidebar", do: nil, else: node
  end

  defp drop_sidebar(node), do: node

  defp id(attrs) do
    Enum.find_value(attrs, fn
      {"id", value} -> value
      _ -> nil
    end)
  end

  test "rail styling stops at the sidebar", %{conn: conn, rail_selectors: rail_selectors} do
    assert rail_selectors != []

    {_railed, outside_sidebar} = conn |> open() |> railed_documents()

    for selector <- rail_selectors do
      assert LazyHTML.to_html(LazyHTML.query(outside_sidebar, selector)) == "",
             "#{selector} styles elements outside #app-sidebar, so collapsing the " <>
               "sidebar to rail restyles them too"
    end
  end

  test "the sidebar's own rows still collapse in rail mode", %{
    conn: conn,
    rail_selectors: rail_selectors
  } do
    {railed, _outside_sidebar} = conn |> open() |> railed_documents()

    labels = LazyHTML.to_html(LazyHTML.query(railed, "#app-sidebar .app-nav-label"))
    assert labels != ""

    assert Enum.any?(rail_selectors, fn selector ->
             LazyHTML.to_html(LazyHTML.query(railed, selector)) == labels
           end),
           "no rail rule hides the sidebar's own nav labels"
  end
end
