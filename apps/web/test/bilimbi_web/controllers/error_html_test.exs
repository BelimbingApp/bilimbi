defmodule BilimbiWeb.ErrorHTMLTest do
  use BilimbiWeb.ConnCase, async: true

  import Phoenix.Template, only: [render_to_string: 4]

  test "renders 404.html" do
    html = render_to_string(BilimbiWeb.ErrorHTML, "404", "html", %{})

    assert html =~ ~s(id="error-not-found")
    assert html =~ ~s(id="error-not-found-home")
    assert html =~ ~s(href="/")
  end

  test "renders 500.html" do
    html = render_to_string(BilimbiWeb.ErrorHTML, "500", "html", %{})

    assert html =~ ~s(id="error-unavailable")
    assert html =~ ~s(id="error-unavailable-home")
    assert html =~ ~s(href="/")
  end

  test "an unknown address is the product 404 page", %{conn: conn} do
    html = conn |> get("/not-a-page") |> html_response(404)

    assert html =~ ~s(id="error-not-found")
    assert html =~ ~s(id="error-not-found-home")
  end
end
