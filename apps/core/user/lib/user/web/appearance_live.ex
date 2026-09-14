defmodule Bilimbi.Core.User.Web.AppearanceLive do
  @moduledoc """
  The signed-in account's self-service theme and locale settings screen.

  Ports Belimbing's `app/Core/User/Livewire/Settings/Appearance.php`.
  Identity comes only from the authenticated scope. Submitted values cannot
  name another user, and locale persistence stays behind Base Locale's public
  explicit-scope API.
  """

  use Bilimbi.Base.UI, :live_view

  # Self-service: `save` writes the signed-in actor's own theme and locale
  # preference under their own settings scope. No admin capability applies
  # (#420).
  @write_guard_opt_out ~w(save)

  import Bilimbi.Core.User.Web.SettingsComponents

  alias Bilimbi.Base.Locale
  alias Bilimbi.Base.Settings.Scope, as: SettingsScope
  alias Bilimbi.Base.Tenancy.Scope, as: TenancyScope
  alias Bilimbi.Core.User.DisplayPreferences

  @impl true
  def mount(_params, _session, socket) do
    current_scope = socket.assigns.current_scope
    locale_scope = locale_scope(current_scope)

    locale =
      if Locale.overridden?(locale_scope), do: Locale.locale(locale_scope), else: ""

    installation_locale = Locale.locale(nil)

    locale_options =
      Locale.supported_locales()
      |> Enum.map(fn {code, %{label: label}} -> {"#{label} (#{code})", code} end)
      |> Enum.sort()

    {:ok,
     assign(socket,
       locale: locale,
       locale_options: locale_options,
       installation_locale: Locale.label(installation_locale),
       timezone_mode_options: timezone_mode_options()
     )}
  end

  @impl true
  def handle_event("save", %{"appearance" => appearance}, socket) when is_map(appearance) do
    current_scope = socket.assigns.current_scope
    preferences = current_scope.shell_preferences
    theme = Map.get(appearance, "theme", preferences.theme)
    locale = Map.get(appearance, "locale", socket.assigns.locale)
    timezone_mode = Map.get(appearance, "timezone_mode", to_string(preferences.mode))

    save_appearance(socket, current_scope, theme, locale, timezone_mode)
  end

  def handle_event("save", _params, socket) do
    {:noreply, socket}
  end

  defp save_appearance(socket, current_scope, theme, locale, timezone_mode) do
    with :ok <- validate_locale(locale),
         :ok <- DisplayPreferences.save(current_scope, "theme", theme),
         :ok <- DisplayPreferences.save(current_scope, "timezone", timezone_mode),
         :ok <- persist_locale(locale_scope(current_scope), locale) do
      {:noreply,
       socket
       |> assign(:current_scope, DisplayPreferences.refresh(current_scope))
       |> assign(:locale, locale)
       |> put_flash(:info, "Appearance settings saved.")}
    else
      {:error, :impersonating} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Display preferences belong to the account you are viewing and were not changed."
         )}

      {:error, :invalid_preference} ->
        {:noreply,
         put_flash(socket, :error, "Choose a supported theme, locale, and time zone display.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not save appearance settings.")}
    end
  end

  defp persist_locale(scope, ""), do: Locale.delete(scope)

  defp persist_locale(scope, locale) do
    case Locale.put(scope, locale) do
      {:ok, _locale} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp locale_scope(current_scope) do
    SettingsScope.user(
      extract_user_id(current_scope),
      extract_company_id(current_scope),
      TenancyScope.tenant_id(current_scope.scope)
    )
  end

  defp timezone_mode_options do
    [
      {"Company time", "company"},
      {"This device's local time", "local"},
      {"Stored UTC", "utc"}
    ]
  end

  defp validate_locale(""), do: :ok

  defp validate_locale(locale) do
    if Locale.supports?(locale), do: :ok, else: {:error, :invalid_preference}
  end

  defp extract_user_id(%{user: %{"user_id" => id}}), do: id
  defp extract_user_id(%{user: %{user_id: id}}), do: id
  defp extract_user_id(%{user: %{id: id}}), do: id
  defp extract_user_id(%{actor: %{id: id}}), do: id

  defp extract_company_id(%{user: %{"company_id" => id}}), do: id
  defp extract_company_id(%{user: %{company_id: id}}), do: id
  defp extract_company_id(%{actor: %{company_id: id}}), do: id
end
