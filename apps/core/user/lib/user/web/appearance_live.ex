defmodule Bilimbi.Core.User.Web.AppearanceLive do
  @moduledoc """
  The signed-in account's self-service theme and appearance settings screen.

  Ports Belimbing's `app/Core/User/Livewire/Settings/Appearance.php`.
  Supports choosing `light`, `dark`, or `system` (device default) appearance.
  """

  use Bilimbi.Base.UI, :live_view

  import Bilimbi.Core.User.Web.SettingsComponents

  alias Bilimbi.Core.User

  @theme_key "ui.theme"

  @impl true
  def mount(_params, _session, socket) do
    current_scope = socket.assigns.current_scope
    user_id = extract_user_id(current_scope)
    company_id = extract_company_id(current_scope)
    scope = current_scope.scope

    theme =
      with {:ok, saved_theme} <- User.get_user_preference(scope, company_id, user_id, @theme_key),
           true <- saved_theme in ["light", "dark", "system"] do
        saved_theme
      else
        _ -> "system"
      end

    {:ok, assign(socket, theme: theme)}
  end

  @impl true
  def handle_event("save", %{"appearance" => %{"theme" => theme}}, socket)
      when theme in ["light", "dark", "system"] do
    current_scope = socket.assigns.current_scope
    user_id = extract_user_id(current_scope)
    company_id = extract_company_id(current_scope)
    scope = current_scope.scope

    result =
      if theme == "system" do
        User.delete_user_preference(scope, company_id, user_id, @theme_key)
      else
        User.put_user_preference(scope, company_id, user_id, @theme_key, theme)
      end

    case result do
      :ok ->
        socket =
          socket
          |> assign(theme: theme)
          |> put_flash(:info, "Appearance settings saved.")
          |> push_event("theme-changed", %{theme: theme})

        {:noreply, socket}

      {:ok, _val} ->
        socket =
          socket
          |> assign(theme: theme)
          |> put_flash(:info, "Appearance settings saved.")
          |> push_event("theme-changed", %{theme: theme})

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not save appearance settings.")}
    end
  end

  def handle_event("save", _params, socket) do
    {:noreply, socket}
  end

  defp extract_user_id(%{user: %{"user_id" => id}}), do: id
  defp extract_user_id(%{user: %{user_id: id}}), do: id
  defp extract_user_id(%{user: %{id: id}}), do: id
  defp extract_user_id(%{actor: %{id: id}}), do: id

  defp extract_company_id(%{user: %{"company_id" => id}}), do: id
  defp extract_company_id(%{user: %{company_id: id}}), do: id
  defp extract_company_id(%{actor: %{company_id: id}}), do: id
end
