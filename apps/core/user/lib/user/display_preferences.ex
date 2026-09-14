defmodule Bilimbi.Core.User.DisplayPreferences do
  @moduledoc """
  The signed-in account's theme and timestamp display preferences.

  One resolved snapshot and one durable write serve every surface that shows
  them: the shell's top-bar controls, the appearance screen and the HTTP
  adapter. Callers hand in the authenticated scope and never name a user, so
  a session that is viewing another account is refused once, here, rather
  than at each caller.

  `presentation/1` is resolved once per request or LiveView process and
  carried on `current_scope.shell_preferences`; `refresh/1` re-resolves it
  after a confirmed write and re-arms the per-process timestamp context.
  """

  alias Bilimbi.Base.DateTime, as: DateTimePolicy
  alias Bilimbi.Base.Settings.Scope, as: SettingsScope
  alias Bilimbi.Base.UI.DateTimeDisplay
  alias Bilimbi.Core.User

  @theme_key "ui.theme"
  @themes ["light", "dark", "system"]

  @doc """
  The account's resolved theme and timestamp display metadata.

  `modes` is `Bilimbi.Base.DateTime.modes/0`, carried so the shell and the
  appearance form offer the canonical set without restating it.
  """
  def presentation(current_scope) do
    user = current_scope.user

    theme =
      case User.get_user_preference(
             current_scope.scope,
             user["company_id"],
             user["user_id"],
             @theme_key
           ) do
        {:ok, theme} when theme in @themes -> theme
        _other -> "system"
      end

    display = DateTimePolicy.display(settings_scope(current_scope), company_scope(current_scope))

    %{
      theme: theme,
      mode: display.mode,
      modes: DateTimePolicy.modes(),
      timezone: display.timezone,
      tz_db: display.tz_db
    }
  end

  @doc """
  Re-resolves the snapshot after a write and returns the updated scope.

  The per-process timestamp context is re-armed from the same snapshot, so a
  timestamp the page renders after this call uses the mode just saved.
  """
  def refresh(current_scope) do
    preferences = presentation(current_scope)
    DateTimeDisplay.put(preferences)
    Map.put(current_scope, :shell_preferences, preferences)
  end

  @doc """
  Stores one display preference for the authenticated account.

  `kind` is `"theme"` or `"timezone"`. An unsupported kind or value is
  refused rather than guessed, and a session that is impersonating cannot
  write the preferences of the account it is viewing.
  """
  def save(current_scope, kind, value) do
    case own_account(current_scope) do
      :ok -> write(current_scope, kind, value)
      {:error, _reason} = error -> error
    end
  end

  defp write(current_scope, "theme", theme) when theme in @themes do
    user = current_scope.user

    result =
      if theme == "system" do
        User.delete_user_preference(
          current_scope.scope,
          user["company_id"],
          user["user_id"],
          @theme_key
        )
      else
        User.put_user_preference(
          current_scope.scope,
          user["company_id"],
          user["user_id"],
          @theme_key,
          theme
        )
      end

    case result do
      :ok -> :ok
      {:ok, _value} -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp write(current_scope, "timezone", mode) do
    case DateTimePolicy.put_mode(settings_scope(current_scope), mode) do
      {:ok, _mode} -> :ok
      {:error, :invalid_mode} -> {:error, :invalid_preference}
      {:error, _reason} = error -> error
    end
  end

  defp write(_current_scope, _kind, _value), do: {:error, :invalid_preference}

  defp own_account(%{impersonator: nil}), do: :ok
  defp own_account(%{impersonator: _impersonator}), do: {:error, :impersonating}

  defp settings_scope(%{user: user, scope: scope}),
    do: SettingsScope.user(user["user_id"], user["company_id"], scope.tenant.id)

  defp company_scope(%{user: user, scope: scope}),
    do: SettingsScope.company(user["company_id"], scope.tenant.id)
end
