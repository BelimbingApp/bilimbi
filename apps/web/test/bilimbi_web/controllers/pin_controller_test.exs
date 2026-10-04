defmodule BilimbiWeb.PinControllerTest do
  use BilimbiWeb.ConnCase, async: false

  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup do
    UserFixtures.create_user_tables!()
    UserFixtures.create_user_pins_table!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})

    UserFixtures.insert_user!(%{
      id: 91,
      company_id: 73,
      name: "Ada Lovelace",
      email: "ada@example.com"
    })

    UserFixtures.insert_user!(%{
      id: 92,
      company_id: 73,
      name: "Grace Hopper",
      email: "grace@example.com"
    })

    :ok
  end

  test "POST /api/pins/toggle requires authentication", %{conn: conn} do
    conn = post(conn, ~p"/api/pins/toggle", %{"label" => "Companies", "url" => "/companies"})
    assert redirected_to(conn) == ~p"/"
  end

  test "GET /api/pins returns only pins whose routes are served", %{conn: conn} do
    {:ok, :pinned, _} =
      User.toggle_user_pin(pin_scope(91), %{"label" => "Companies", "url" => "/companies"})

    {:ok, :pinned, _} =
      User.toggle_user_pin(pin_scope(91), %{"label" => "Gone", "url" => "/gone"})

    response =
      conn
      |> log_in_as()
      |> put_req_header("accept", "application/json")
      |> get(~p"/api/pins")
      |> json_response(200)

    assert Enum.map(response["pins"], & &1["url"]) == ["/companies"]
  end

  test "POST /api/pins/toggle pins and unpins URLs", %{conn: conn} do
    conn =
      conn
      |> log_in_as()
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/pins/toggle", %{
        "label" => "Admin / Companies",
        "url" => "/companies",
        "icon" => "hero-building-office"
      })

    response = json_response(conn, 200)
    assert response["pinned"] == true
    assert length(response["pins"]) == 1
    assert hd(response["pins"])["label"] == "Companies"
    assert hd(response["pins"])["url"] == "/companies"

    # Toggling again removes it
    conn2 =
      build_conn()
      |> log_in_as()
      |> post(~p"/api/pins/toggle", %{
        "label" => "Companies",
        "url" => "/companies"
      })

    response2 = json_response(conn2, 200)
    assert response2["pinned"] == false
    assert response2["pins"] == []
  end

  test "POST /api/pins/reorder updates pin sort order", %{conn: conn} do
    {:ok, :pinned, _} =
      User.toggle_user_pin(pin_scope(91), %{"label" => "Pin 1", "url" => "/page1"})

    {:ok, :pinned, [pin1, pin2]} =
      User.toggle_user_pin(pin_scope(91), %{"label" => "Pin 2", "url" => "/page2"})

    conn =
      conn
      |> log_in_as()
      |> post(~p"/api/pins/reorder", %{
        "pins" => [%{"id" => pin2.id}, %{"id" => pin1.id}]
      })

    response = json_response(conn, 200)
    assert Enum.map(response["pins"], & &1["id"]) == [pin2.id, pin1.id]
    assert Enum.map(response["pins"], & &1["sort_order"]) == [0, 1]
  end

  # `String.to_integer/1` raises on anything non-numeric, and the map clauses
  # had no catch-all, so a logged-in client could turn a typo into a 500. This
  # is the crash #302 fixed on the Countries screen, in new code.
  test "POST /api/pins/reorder rejects malformed ids instead of crashing", %{conn: conn} do
    {:ok, :pinned, [pin]} =
      User.toggle_user_pin(pin_scope(91), %{"label" => "Pin 1", "url" => "/page1"})

    signed_in = log_in_as(conn)

    for payload <- [
          ["abc"],
          [%{"id" => "abc"}],
          [%{"id" => nil}],
          [nil],
          [%{"label" => "no id at all"}],
          [%{"id" => to_string(pin.id)}, "12x"]
        ] do
      response =
        signed_in
        |> post(~p"/api/pins/reorder", %{"pins" => payload})
        |> json_response(422)

      assert response == %{"error" => "invalid_parameters"}
    end

    # A numeric string is a legitimate id shape and must still be accepted --
    # a fix that rejected every binary would satisfy every assertion above.
    response =
      signed_in
      |> post(~p"/api/pins/reorder", %{"pins" => [%{"id" => to_string(pin.id)}]})
      |> json_response(200)

    assert Enum.map(response["pins"], & &1["id"]) == [pin.id]
  end

  test "pins remain readable but cannot be changed while impersonating", %{conn: conn} do
    {:ok, :pinned, _} =
      User.toggle_user_pin(pin_scope(91), %{"label" => "Companies", "url" => "/companies"})

    {:ok, :pinned, pins} =
      User.toggle_user_pin(pin_scope(91), %{"label" => "Gone", "url" => "/gone"})

    impersonating =
      conn
      |> log_in_as()
      |> impersonating_as(92, "Grace Hopper")

    response = impersonating |> get(~p"/api/pins") |> json_response(200)
    assert Enum.map(response["pins"], & &1["url"]) == ["/companies"]

    for url <- ["/companies", "/new"] do
      assert json_response(
               post(impersonating, ~p"/api/pins/toggle", %{"label" => "Pin", "url" => url}),
               403
             ) == %{"error" => "impersonating"}
    end

    assert json_response(
             post(impersonating, ~p"/api/pins/reorder", %{
               "pins" => pins |> Enum.reverse() |> Enum.map(& &1.id)
             }),
             403
           ) == %{"error" => "impersonating"}

    assert {:ok, ^pins} = User.list_user_pins(pin_scope(91))
  end

  test "Accept: application/json lists, pins, unpins, and reorders only that account" do
    {:ok, :pinned, _} =
      User.toggle_user_pin(pin_scope(92), %{
        "label" => "Notifications",
        "url" => "/notifications"
      })

    assert json_response(get(signed_in_json(), ~p"/api/pins"), 200)["pins"] == []

    pinned =
      signed_in_json()
      |> post_json(~p"/api/pins/toggle", %{"label" => "Companies", "url" => "/companies"})
      |> json_response(200)

    assert pinned["pinned"] == true
    assert Enum.map(pinned["pins"], & &1["url"]) == ["/companies"]

    both =
      signed_in_json()
      |> post_json(~p"/api/pins/toggle", %{"label" => "Profile", "url" => "/settings/profile"})
      |> json_response(200)

    assert Enum.map(both["pins"], & &1["url"]) == ["/companies", "/settings/profile"]
    [companies_id, profile_id] = Enum.map(both["pins"], & &1["id"])

    reordered =
      signed_in_json()
      |> post_json(~p"/api/pins/reorder", %{
        "pins" => [%{"id" => profile_id}, %{"id" => companies_id}]
      })
      |> json_response(200)

    assert Enum.map(reordered["pins"], & &1["url"]) == ["/settings/profile", "/companies"]

    unpinned =
      signed_in_json()
      |> post_json(~p"/api/pins/toggle", %{"label" => "Companies", "url" => "/companies"})
      |> json_response(200)

    assert unpinned["pinned"] == false
    assert Enum.map(unpinned["pins"], & &1["url"]) == ["/settings/profile"]

    listed = signed_in_json() |> get(~p"/api/pins") |> json_response(200)
    assert Enum.map(listed["pins"], & &1["url"]) == ["/settings/profile"]

    assert {:ok, [other]} = User.list_user_pins(pin_scope(92))
    assert other.url == "/notifications"

    impersonating = impersonating_json()

    visible = impersonating |> get(~p"/api/pins") |> json_response(200)
    assert Enum.map(visible["pins"], & &1["url"]) == ["/settings/profile"]

    assert json_response(
             post_json(impersonating_json(), ~p"/api/pins/toggle", %{
               "label" => "Notifications",
               "url" => "/notifications"
             }),
             403
           ) == %{"error" => "impersonating"}

    assert json_response(
             post_json(impersonating_json(), ~p"/api/pins/reorder", %{
               "pins" => [%{"id" => profile_id}]
             }),
             403
           ) == %{"error" => "impersonating"}

    assert {:ok, [unchanged]} = User.list_user_pins(pin_scope(91))
    assert unchanged.url == "/settings/profile"
    assert {:ok, [still_other]} = User.list_user_pins(pin_scope(92))
    assert still_other.url == "/notifications"
  end

  defp signed_in_json do
    build_conn()
    |> put_req_header("accept", "application/json")
    |> log_in_as()
  end

  defp impersonating_json do
    signed_in_json()
    |> impersonating_as(92, "Grace Hopper")
  end

  defp post_json(conn, path, payload) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post(path, Phoenix.json_library().encode!(payload))
  end

  defp pin_scope(user_id) do
    {:ok, scope} = Bilimbi.Base.Tenancy.scope(41)
    Bilimbi.Base.Tenancy.Authentication.sign_in(scope, user_id, 73)
  end
end
