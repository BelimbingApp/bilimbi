defmodule BilimbiWeb.PageController do
  use BilimbiWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
