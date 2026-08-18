defmodule BilimbiWeb.ThemeController do
  @moduledoc """
  REST endpoint for updating the authenticated user's UI theme preference (`POST /api/theme`).
  """

  use BilimbiWeb, :controller

  alias Bilimbi.Core.User

  @theme_key "ui.theme"

  def update(conn, %{"theme" => theme}) when theme in ["light", "dark", "system"] do
    scope = conn.assigns[:current_scope]

    if scope && scope[:user] do
      user_id = extract_user_id(scope)
      company_id = extract_company_id(scope)
      tenant_scope = scope.scope

      if theme == "system" do
        User.delete_user_preference(tenant_scope, company_id, user_id, @theme_key)
      else
        User.put_user_preference(tenant_scope, company_id, user_id, @theme_key, theme)
      end

      json(conn, %{theme: theme})
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "unauthorized"})
    end
  end

  def update(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "invalid_theme"})
  end

  defp extract_user_id(%{user: %{"user_id" => id}}), do: id
  defp extract_user_id(%{user: %{user_id: id}}), do: id
  defp extract_user_id(%{user: %{id: id}}), do: id
  defp extract_user_id(%{actor: %{id: id}}), do: id

  defp extract_company_id(%{user: %{"company_id" => id}}), do: id
  defp extract_company_id(%{user: %{company_id: id}}), do: id
  defp extract_company_id(%{actor: %{company_id: id}}), do: id
end
