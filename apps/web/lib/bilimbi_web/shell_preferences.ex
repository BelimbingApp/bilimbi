defmodule BilimbiWeb.ShellPreferences do
  @moduledoc "Authenticated shell preference adapter. Identity always comes from the live session."

  alias Bilimbi.Base.DateTime, as: DateTimePolicy
  alias Bilimbi.Base.Settings.Scope, as: SettingsScope
  alias Bilimbi.Base.UI.DateTimeDisplay
  alias Bilimbi.Core.User

  def presentation(current_scope) do
    user = current_scope.user

    {:ok, theme} =
      User.get_user_preference(
        current_scope.scope,
        user["company_id"],
        user["user_id"],
        "ui.theme"
      )

    display = DateTimePolicy.display(settings_scope(current_scope), company_scope(current_scope))

    %{theme: theme || "system", mode: display.mode, timezone: display.timezone}
  end

  def attach(socket) do
    Phoenix.LiveView.attach_hook(socket, :shell_preferences, :handle_event, &handle_event/3)
  end

  def handle_event("shell:preference", %{"kind" => kind, "value" => value}, socket) do
    # Rehydrate the durable session before a self-service write, just as the
    # HTTP preference endpoint does. A revoked session cannot keep writing.
    with {:ok, current_scope} <- BilimbiWeb.UserAuth.refresh_scope(socket.assigns.current_scope),
         :ok <- save(current_scope, kind, value) do
      preferences =
        case kind do
          "theme" -> %{current_scope.shell_preferences | theme: value}
          "timezone" -> %{current_scope.shell_preferences | mode: mode(value)}
        end

      current_scope = Map.put(current_scope, :shell_preferences, preferences)

      DateTimeDisplay.put(%{
        mode: preferences.mode,
        timezone: preferences.timezone,
        tz_db: DateTimePolicy.time_zone_database()
      })

      socket = Phoenix.Component.assign(socket, :current_scope, current_scope)
      {:halt, %{ok: true, preferences: preferences}, socket}
    else
      {:error, _reason} -> {:halt, %{ok: false}, socket}
    end
  rescue
    _error in [Postgrex.Error, DBConnection.ConnectionError] ->
      {:halt, %{ok: false}, socket}
  end

  def handle_event("shell:preference", _params, socket), do: {:halt, %{ok: false}, socket}
  def handle_event(_event, _params, socket), do: {:cont, socket}

  def save(current_scope, "theme", theme) when theme in ["light", "dark", "system"] do
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

  def save(current_scope, "timezone", mode) when mode in ["company", "local", "utc"] do
    case DateTimePolicy.put_mode(settings_scope(current_scope), mode) do
      {:ok, _mode} -> :ok
      {:error, _reason} = error -> error
    end
  end

  def save(_scope, _kind, _value), do: {:error, :invalid_preference}

  defp mode("company"), do: :company
  defp mode("local"), do: :local
  defp mode("utc"), do: :utc

  defp settings_scope(%{user: user, scope: scope}),
    do: SettingsScope.user(user["user_id"], user["company_id"], scope.tenant.id)

  defp company_scope(%{user: user, scope: scope}),
    do: SettingsScope.company(user["company_id"], scope.tenant.id)
end
