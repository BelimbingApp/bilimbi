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

  alias Bilimbi.Base.DateTime, as: DateTimePolicy
  alias Bilimbi.Base.Locale
  alias Bilimbi.Base.Settings.Scope, as: SettingsScope
  alias Bilimbi.Base.Tenancy.Scope, as: TenancyScope
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

    locale_scope = locale_scope(current_scope)

    locale =
      if Locale.overridden?(locale_scope), do: Locale.locale(locale_scope), else: ""

    installation_locale = Locale.locale(nil)

    locale_options =
      Locale.supported_locales()
      |> Enum.map(fn {code, %{label: label}} -> {"#{label} (#{code})", code} end)
      |> Enum.sort()

    settings_scope = locale_scope(current_scope)

    timezone_mode =
      if DateTimePolicy.mode_overridden?(settings_scope) do
        Atom.to_string(DateTimePolicy.mode(settings_scope))
      else
        ""
      end

    {:ok,
     assign(socket,
       theme: theme,
       locale: locale,
       locale_options: locale_options,
       installation_locale: Locale.label(installation_locale),
       timezone_mode: timezone_mode,
       timezone_mode_options: timezone_mode_options()
     )}
  end

  @impl true
  def handle_event("save", %{"appearance" => appearance}, socket) when is_map(appearance) do
    theme = Map.get(appearance, "theme", socket.assigns.theme)
    locale = Map.get(appearance, "locale", socket.assigns.locale)
    timezone_mode = Map.get(appearance, "timezone_mode", socket.assigns.timezone_mode)

    if valid_theme?(theme) and valid_locale?(locale) and valid_timezone_mode?(timezone_mode) do
      save_appearance(socket, theme, locale, timezone_mode)
    else
      {:noreply,
       put_flash(socket, :error, "Choose a supported theme, locale, and time zone display.")}
    end
  end

  def handle_event("save", _params, socket) do
    {:noreply, socket}
  end

  defp save_appearance(socket, theme, locale, timezone_mode) do
    current_scope = socket.assigns.current_scope
    user_id = extract_user_id(current_scope)
    company_id = extract_company_id(current_scope)
    scope = current_scope.scope

    with :ok <- persist_theme(scope, company_id, user_id, theme),
         :ok <- persist_locale(locale_scope(current_scope), locale),
         :ok <- persist_timezone_mode(locale_scope(current_scope), timezone_mode) do
      {:noreply,
       socket
       |> assign(theme: theme, locale: locale, timezone_mode: timezone_mode)
       |> put_flash(:info, "Appearance settings saved.")
       |> push_event("theme-changed", %{theme: theme})}
    else
      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not save appearance settings.")}
    end
  end

  defp persist_theme(scope, company_id, user_id, "system") do
    User.delete_user_preference(scope, company_id, user_id, @theme_key)
  end

  defp persist_theme(scope, company_id, user_id, theme) do
    case User.put_user_preference(scope, company_id, user_id, @theme_key, theme) do
      {:ok, _theme} -> :ok
      {:error, reason} -> {:error, reason}
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

  defp persist_timezone_mode(scope, ""), do: DateTimePolicy.delete_mode(scope)

  defp persist_timezone_mode(scope, mode) do
    case DateTimePolicy.put_mode(scope, mode) do
      {:ok, _mode} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp timezone_mode_options do
    [
      {"Use default (Company time)", ""},
      {"Company time", "company"},
      {"This device's local time", "local"},
      {"Stored UTC", "utc"}
    ]
  end

  defp valid_theme?(theme), do: theme in ["light", "dark", "system"]
  defp valid_locale?(""), do: true
  defp valid_locale?(locale), do: Locale.supports?(locale)

  defp valid_timezone_mode?(""), do: true
  defp valid_timezone_mode?(mode), do: DateTimePolicy.valid_mode?(mode)

  defp extract_user_id(%{user: %{"user_id" => id}}), do: id
  defp extract_user_id(%{user: %{user_id: id}}), do: id
  defp extract_user_id(%{user: %{id: id}}), do: id
  defp extract_user_id(%{actor: %{id: id}}), do: id

  defp extract_company_id(%{user: %{"company_id" => id}}), do: id
  defp extract_company_id(%{user: %{company_id: id}}), do: id
  defp extract_company_id(%{actor: %{company_id: id}}), do: id
end
