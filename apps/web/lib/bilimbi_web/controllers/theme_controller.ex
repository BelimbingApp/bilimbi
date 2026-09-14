defmodule BilimbiWeb.ThemeController do
  @moduledoc "Authenticated HTTP adapter for the same theme write used by the shell."
  use BilimbiWeb, :controller

  def update(conn, %{"theme" => theme}) when theme in ["light", "dark", "system"] do
    case BilimbiWeb.ShellPreferences.save(conn.assigns.current_scope, "theme", theme) do
      :ok ->
        json(conn, %{theme: theme})

      {:error, _reason} ->
        conn |> put_status(:service_unavailable) |> json(%{error: "save_failed"})
    end
  rescue
    _error in [Postgrex.Error, DBConnection.ConnectionError] ->
      conn |> put_status(:service_unavailable) |> json(%{error: "save_failed"})
  end

  def update(conn, _params),
    do: conn |> put_status(:unprocessable_entity) |> json(%{error: "invalid_theme"})
end
