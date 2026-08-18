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

    :ok
  end

  test "POST /api/pins/toggle requires authentication", %{conn: conn} do
    conn = post(conn, ~p"/api/pins/toggle", %{"label" => "Companies", "url" => "/companies"})
    assert redirected_to(conn) == ~p"/"
  end

  test "POST /api/pins/toggle pins and unpins URLs", %{conn: conn} do
    conn =
      conn
      |> log_in_as()
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
    {:ok, :pinned, _} = User.toggle_user_pin(91, %{"label" => "Pin 1", "url" => "/page1"})

    {:ok, :pinned, [pin1, pin2]} =
      User.toggle_user_pin(91, %{"label" => "Pin 2", "url" => "/page2"})

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
    {:ok, :pinned, [pin]} = User.toggle_user_pin(91, %{"label" => "Pin 1", "url" => "/page1"})

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
end
