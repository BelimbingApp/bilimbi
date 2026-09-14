defmodule BilimbiWeb.ShellPreferences do
  @moduledoc "Authenticated shell preference adapter. Identity always comes from the live session."

  alias Bilimbi.Base.DateTime, as: DateTimePolicy
  alias Bilimbi.Base.Settings.Scope, as: SettingsScope
  alias Bilimbi.Base.UI.DateTimeDisplay
  alias Bilimbi.Core.User

  @doc """
  The one resolved display snapshot for a scope lifecycle: the account's theme
  plus the `Bilimbi.Base.DateTime` display metadata. `UserAuth` carries it on
  `current_scope.shell_preferences`, stamps the root layout from it and hands
  it straight to `DateTimeDisplay`, so nothing re-reads these preferences.
  """
  def presentation(current_scope) do
    user = current_scope.user

    theme =
      case User.get_user_preference(
             current_scope.scope,
             user["company_id"],
             user["user_id"],
             "ui.theme"
           ) do
        {:ok, theme} when theme in ["light", "dark", "system"] -> theme
        _other -> "system"
      end

    display = DateTimePolicy.display(settings_scope(current_scope), company_scope(current_scope))

    %{theme: theme, mode: display.mode, timezone: display.timezone, tz_db: display.tz_db}
  end

  def attach(socket),
    do: Phoenix.LiveView.attach_hook(socket, :shell_preferences, :handle_event, &handle_event/3)

  def handle_event("shell:preference", %{"kind" => kind, "value" => value}, socket) do
    # Rehydrate the durable session before a self-service write, just as the
    # HTTP preference endpoint does. A revoked session cannot keep writing.
    with {:ok, current_scope} <- BilimbiWeb.UserAuth.refresh_scope(socket.assigns.current_scope),
         :ok <- save(current_scope, kind, value) do
      {:halt, %{ok: true}, confirm(socket, current_scope)}
    else
      {:error, _reason} -> {:halt, %{ok: false}, socket}
    end
  rescue
    _error in [Postgrex.Error, DBConnection.ConnectionError] ->
      {:halt, %{ok: false}, socket}
  end

  def handle_event("shell:preference", _params, socket), do: {:halt, %{ok: false}, socket}
  def handle_event(_event, _params, socket), do: {:cont, socket}

  @doc """
  The one durable write for a display preference, shared by the shell hook and
  the HTTP adapter. An impersonated session is refused here, so no caller can
  change the preferences of the account it is viewing.
  """
  def save(current_scope, kind, value) do
    case own_account(current_scope) do
      :ok -> write(current_scope, kind, value)
      {:error, _reason} = error -> error
    end
  end

  defp write(current_scope, "theme", theme) when theme in ["light", "dark", "system"] do
    user = current_scope.user

    result =
      if theme == "system" do
        User.delete_user_preference(
          current_scope.scope,
          user["company_id"],
          user["user_id"],
          "ui.theme"
        )
      else
        User.put_user_preference(
          current_scope.scope,
          user["company_id"],
          user["user_id"],
          "ui.theme",
          theme
        )
      end

    case result do
      :ok -> :ok
      {:ok, _value} -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp write(current_scope, "timezone", mode) when mode in ["company", "local", "utc"] do
    case DateTimePolicy.put_mode(settings_scope(current_scope), mode) do
      {:ok, _mode} -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp write(_scope, _kind, _value), do: {:error, :invalid_preference}

  defp confirm(socket, current_scope) do
    preferences = presentation(current_scope)
    DateTimeDisplay.put(preferences)

    Phoenix.Component.assign(
      socket,
      :current_scope,
      Map.put(current_scope, :shell_preferences, preferences)
    )
  end

  defp own_account(%{impersonator: nil}), do: :ok
  defp own_account(%{impersonator: _impersonator}), do: {:error, :impersonating}

  defp settings_scope(%{user: user, scope: scope}),
    do: SettingsScope.user(user["user_id"], user["company_id"], scope.tenant.id)

  defp company_scope(%{user: user, scope: scope}),
    do: SettingsScope.company(user["company_id"], scope.tenant.id)
end
