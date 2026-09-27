defmodule Bilimbi.Base.Tiling.WorkspaceFollowTest do
  @moduledoc """
  The follow channel through the real host: the token every frame carries,
  the tile that follows a kind of record, the fact that moves it, and the
  Company list and record pages that announce inside a workspace.
  """

  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.UI.Workspace
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  @companies "admin.company.list"
  @company "admin.company.view"

  setup do
    UserFixtures.create_user_tables!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})

    CompanyFixtures.insert_company!(%{
      id: 74,
      tenant_id: 41,
      name: "Second Company",
      code: "second-company"
    })

    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})
    grant_capabilities!([@companies, @company])
    :ok
  end

  defp framed(conn), do: put_req_header(conn, "sec-fetch-dest", "iframe")

  defp join(view) do
    token = Workspace.host_token(view.id)
    topic = Workspace.topic(41, 91, token)
    :ok = Workspace.subscribe(topic)
    {token, topic}
  end

  test "every frame carries the workspace token, and a frame's report drops it", %{conn: conn} do
    {:ok, view, _html} = conn |> log_in_as() |> live("/workspace?t=/companies")
    token = Workspace.host_token(view.id)

    assert has_element?(view, "#tile-t1-page[src='/companies?ws=#{token}']")
    assert has_element?(view, "#tile-t1-header-open-alone[href='/companies']")

    render_hook(view, "tile-navigated", %{
      "id" => "t1",
      "path" => "/companies?page=2&ws=#{token}",
      "title" => "Companies"
    })

    assert_patch(view, "/workspace?t=%2Fcompanies%3Fpage%3D2")
    assert has_element?(view, "#tile-t1-header-open-alone[href='/companies?page=2']")
  end

  test "a record tile follows selections, and a selected record moves it", %{conn: conn} do
    {:ok, view, _html} =
      conn |> log_in_as() |> live("/workspace?t=h.5(/companies,/companies/73)")

    {token, topic} = join(view)

    # Only the tile showing one record can follow.
    refute has_element?(view, "#tile-t1-header-follow")
    assert has_element?(view, "#tile-t2-header-follow", "Follow selections")
    refute has_element?(view, "#tile-t2-header-following")

    # A page joining the workspace learns that nothing is followed yet.
    :ok = Workspace.broadcast(topic, {:workspace_joined})
    assert_receive {:workspace_follows, []}

    view |> element("#tile-t2-header-follow") |> render_click()

    assert_patch(
      view,
      "/workspace?t=h.5%28%2Fcompanies%2C%2Fcompanies%2F73%3E%2Fcompanies%2F%3Aid%29"
    )

    assert has_element?(view, "#tile-t2-header-following[title='Follows selections']")
    assert has_element?(view, "#tile-t2-header-follow", "Stop following")
    assert_receive {:workspace_follows, ["core/company"]}

    # A company selected elsewhere moves the following tile there, once.
    :ok = Workspace.broadcast(topic, {:workspace_fact, %{kind: "core/company", id: 74}})
    assert_push_event(view, "tile-navigate", %{id: "t2", path: path})
    assert path == "/companies/74?ws=#{token}"

    assert_patch(
      view,
      "/workspace?t=h.5%28%2Fcompanies%2C%2Fcompanies%2F74%3E%2Fcompanies%2F%3Aid%29"
    )

    assert has_element?(view, "#tile-t2-header-title", "/companies/74")

    :ok = Workspace.broadcast(topic, {:workspace_fact, %{kind: "core/company", id: 74}})
    :ok = Workspace.broadcast(topic, {:workspace_fact, %{kind: "core/user", id: 91}})
    :ok = Workspace.broadcast(topic, {:workspace_fact, %{kind: "core/company", id: "../x"}})
    _ = render(view)
    refute_receive {_ref, {:push_event, "tile-navigate", _payload}}
    assert has_element?(view, "#tile-t2-header-title", "/companies/74")

    # The following tile keeps its place through a swap, and stops on request.
    view |> element("#tile-t2-header-swap") |> render_click()
    assert has_element?(view, "#tile-t2-header-following")

    view |> element("#tile-t2-header-follow") |> render_click()
    assert_patch(view, "/workspace?t=h.5%28%2Fcompanies%2F74%2C%2Fcompanies%29")
    refute has_element?(view, "#tile-t2-header-following")
    assert_receive {:workspace_follows, []}
  end

  test "a followed pattern survives the address and a saved layout", %{conn: conn} do
    {:ok, view, _html} =
      conn
      |> log_in_as()
      |> live("/workspace?t=h.5(/companies,/companies/73>/companies/:id)")

    assert has_element?(view, "#tile-t2-header-following")
    assert has_element?(view, "#tile-t1-page[src^='/companies?ws=']")

    view |> element("#workspace-open-layouts") |> render_click()

    view
    |> form("#workspace-save-form", layout: %{label: "Company desk"})
    |> render_submit()

    assert_patch(view, "/workspace/company-desk")

    {:ok, reopened, _html} = conn |> log_in_as() |> live("/workspace/company-desk")
    assert has_element?(reopened, "#tile-t2-header-following")
  end

  test "a framed Company list opens a row alone and selects it once a tile follows companies", %{
    conn: conn
  } do
    token = Workspace.host_token("phx-a-host")
    topic = Workspace.topic(41, 91, token)
    :ok = Workspace.subscribe(topic)

    {:ok, list, _html} = conn |> log_in_as() |> framed() |> live("/companies?ws=#{token}")
    assert_receive {:workspace_joined}

    # In a tile the row is a selection; with nothing following companies it
    # opens the record, as the link does alone.
    row =
      "#companies button[data-record-select][phx-value-id='73'][phx-value-path='/companies/73']"

    assert has_element?(list, row, "Bilimbi Industries")
    refute has_element?(list, "#companies a", "Bilimbi Industries")

    list |> element(row) |> render_click()
    assert_redirect(list, "/companies/73")
    refute_receive {:workspace_fact, _fact}

    # Once a tile follows companies, the same click stays and announces.
    {:ok, list, _html} = conn |> log_in_as() |> framed() |> live("/companies?ws=#{token}")
    assert_receive {:workspace_joined}
    :ok = Workspace.broadcast(topic, {:workspace_follows, ["core/company"]})
    _ = render(list)

    list |> element(row) |> render_click()
    assert_receive {:workspace_fact, %{kind: "core/company", id: "73"}}
    assert has_element?(list, "#companies")
  end

  test "a framed Company page announces the record it shows", %{conn: conn} do
    token = Workspace.host_token("phx-a-host")
    topic = Workspace.topic(41, 91, token)
    :ok = Workspace.subscribe(topic)

    {:ok, _show, _html} = conn |> log_in_as() |> framed() |> live("/companies/73?ws=#{token}")
    assert_receive {:workspace_joined}
    assert_receive {:workspace_fact, %{kind: "core/company", id: 73}}

    # Alone, a token in the address means nothing.
    {:ok, _alone, _html} = conn |> log_in_as() |> live("/companies/73?ws=#{token}")
    refute_receive {:workspace_joined}
    refute_receive {:workspace_fact, _fact}
  end
end
