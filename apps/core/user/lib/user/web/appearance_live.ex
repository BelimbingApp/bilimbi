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
  alias Bilimbi.Base.UI.ShellComponents
  alias Bilimbi.Core.User.DisplayPreferences

  @impl true
  def mount(_params, _session, socket) do
    current_scope = socket.assigns.current_scope
    installation_locale = Locale.locale(nil)

    locale_options =
      Locale.supported_locales()
      |> Enum.map(fn {code, %{label: label}} -> {"#{label} (#{code})", code} end)
      |> Enum.sort()

    {:ok,
     assign(socket,
       locale: stored_locale(locale_scope(current_scope)),
       locale_options: locale_options,
       installation_locale: Locale.label(installation_locale),
       timezone_mode_options: timezone_mode_options(current_scope)
     )}
  end

  @impl true
  def handle_event("save", %{"appearance" => appearance}, socket) when is_map(appearance) do
    current_scope = socket.assigns.current_scope
    preferences = current_scope.shell_preferences

    refused =
      [
        {"Theme",
         DisplayPreferences.save(
           current_scope,
           "theme",
           Map.get(appearance, "theme", preferences.theme)
         )},
        {"Time zone display",
         DisplayPreferences.save(
           current_scope,
           "timezone",
           Map.get(appearance, "timezone_mode", to_string(preferences.mode))
         )},
        {"Language",
         save_locale(current_scope, Map.get(appearance, "locale", socket.assigns.locale))}
      ]
      |> Enum.filter(&match?({_field, {:error, _reason}}, &1))

    {:noreply,
     socket
     |> assign(:current_scope, DisplayPreferences.refresh(current_scope))
     |> assign(:locale, stored_locale(locale_scope(current_scope)))
     |> report(refused)}
  end

  def handle_event("save", _params, socket) do
    {:noreply, socket}
  end

  defp report(socket, []), do: put_flash(socket, :info, "Appearance settings saved.")

  defp report(socket, refused) do
    message =
      refused
      |> Enum.group_by(fn {_field, {:error, reason}} -> reason end, &elem(&1, 0))
      |> Enum.map_join(" ", fn {reason, fields} ->
        "Not saved — #{Enum.join(fields, ", ")}. #{refusal(reason)}"
      end)

    put_flash(socket, :error, message)
  end

  defp refusal(:impersonating),
    do: "Display preferences belong to the account you are viewing."

  defp refusal(:invalid_preference), do: "Choose a supported value."
  defp refusal(_reason), do: "The change could not be saved."

  defp save_locale(current_scope, ""), do: Locale.delete(locale_scope(current_scope))

  defp save_locale(current_scope, locale) do
    if Locale.supports?(locale) do
      case Locale.put(locale_scope(current_scope), locale) do
        {:ok, _locale} -> :ok
        {:error, _reason} = error -> error
      end
    else
      {:error, :invalid_preference}
    end
  end

  defp stored_locale(scope) do
    if Locale.overridden?(scope), do: Locale.locale(scope), else: ""
  end

  defp locale_scope(current_scope) do
    SettingsScope.user(
      extract_user_id(current_scope),
      extract_company_id(current_scope),
      TenancyScope.tenant_id(current_scope.scope)
    )
  end

  defp timezone_mode_options(current_scope) do
    Enum.map(
      current_scope.shell_preferences.modes,
      &{ShellComponents.mode_choice_label(&1), to_string(&1)}
    )
  end

  defp extract_user_id(%{user: %{"user_id" => id}}), do: id
  defp extract_user_id(%{user: %{user_id: id}}), do: id
  defp extract_user_id(%{user: %{id: id}}), do: id
  defp extract_user_id(%{actor: %{id: id}}), do: id

  defp extract_company_id(%{user: %{"company_id" => id}}), do: id
  defp extract_company_id(%{user: %{company_id: id}}), do: id
  defp extract_company_id(%{actor: %{company_id: id}}), do: id
end
