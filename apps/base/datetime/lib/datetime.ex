defmodule Bilimbi.Base.DateTime do
  @moduledoc """
  Company/local/UTC timestamp display policy (#459).

  A small policy boundary, not date arithmetic: business modules keep
  ownership of their stored timestamps and deadline semantics, and canonical
  storage stays UTC (compatible `NaiveDateTime` values are explicitly
  interpreted as UTC). This module owns the user-scoped `ui.timezone.mode`
  preference (`company | local | utc`, default `company`), validates IANA
  identifiers against a real time zone database, and resolves the
  server-authorized `Display` metadata the web edge hands to presentation.

  This module declares both definitions, but Core Company keeps the
  company-timezone management surface and resolution (#447): it writes the
  value through the public Settings API under its own capability, and this
  module reads it by explicit company scope — Base never queries Core.

  The time zone database is `TimeZoneInfo.TimeZoneDatabase`, the same
  explicit-database idiom `base/schedule` established — Elixir's default
  UTC-only database cannot convert zones and is never assumed to.
  """

  alias Bilimbi.Base.DateTime.Display
  alias Bilimbi.Base.Locale
  alias Bilimbi.Base.Settings
  alias Bilimbi.Base.Settings.Scope

  @mode_key "ui.timezone.mode"
  @timezone_key "localization.timezone"

  @modes [:company, :local, :utc]
  @default_mode :company
  @default_timezone "UTC"
  @tz_db TimeZoneInfo.TimeZoneDatabase

  @type mode :: :company | :local | :utc

  @doc "The three display modes, canonical order."
  @spec modes() :: [mode()]
  def modes, do: @modes

  @spec valid_mode?(term()) :: boolean()
  def valid_mode?(mode) when mode in @modes, do: true
  def valid_mode?(mode) when is_binary(mode), do: mode in Enum.map(@modes, &Atom.to_string/1)
  def valid_mode?(_mode), do: false

  @doc "The time zone database presentation shifts run against."
  @spec time_zone_database() :: module()
  def time_zone_database, do: @tz_db

  @doc "Reads the account's display mode; unset or invalid resolves to `:company`."
  @spec mode(Scope.t()) :: mode()
  def mode(%Scope{type: :user} = scope) do
    case Settings.get(@mode_key, scope) do
      value when is_binary(value) -> parse_mode(value)
      _other -> @default_mode
    end
  end

  @doc "Whether the account has its own stored display mode."
  @spec mode_overridden?(Scope.t()) :: boolean()
  def mode_overridden?(%Scope{type: :user} = scope), do: Settings.overridden?(@mode_key, scope)

  @doc """
  Stores the signed-in account's display mode.

  The caller derives `scope` from the authenticated context; a request can
  never name another user here. Only the three canonical modes persist.
  """
  @spec put_mode(Scope.t(), mode() | String.t()) :: {:ok, mode()} | {:error, :invalid_mode}
  def put_mode(%Scope{type: :user} = scope, mode) do
    if valid_mode?(mode) do
      mode = parse_mode(mode)

      case Settings.put(@mode_key, Atom.to_string(mode), scope) do
        {:ok, _value} -> {:ok, mode}
        {:error, _reason} = error -> error
      end
    else
      {:error, :invalid_mode}
    end
  end

  @doc "Removes the account's stored mode so the default resolves again."
  @spec delete_mode(Scope.t()) :: :ok
  def delete_mode(%Scope{type: :user} = scope), do: Settings.delete(@mode_key, scope)

  @doc "Whether the value names a convertible IANA time zone in the real database."
  @spec valid_timezone?(term()) :: boolean()
  def valid_timezone?(timezone) when is_binary(timezone) do
    match?({:ok, _now}, DateTime.now(timezone, @tz_db))
  end

  def valid_timezone?(_timezone), do: false

  @doc """
  Every convertible IANA identifier, links included, for selection surfaces.

  Links stay in: identifiers like Asia/Kuala_Lumpur are aliases in current
  IANA data, and a company that stored one must keep seeing it offered.
  """
  @spec timezones() :: [String.t()]
  def timezones, do: TimeZoneInfo.time_zones(links: :include)

  @doc """
  Reads the company time zone by explicit company scope; default `UTC`.

  A stored value that no longer names a convertible zone resolves to `UTC`
  rather than raising in presentation — the invalid value stays visible on
  the company management surface, which is where it gets fixed.
  """
  @spec company_timezone(Scope.t() | nil) :: String.t()
  def company_timezone(nil), do: @default_timezone

  def company_timezone(%Scope{} = scope) do
    case Settings.get(@timezone_key, scope) do
      value when is_binary(value) and value != "" ->
        if valid_timezone?(value), do: value, else: @default_timezone

      _other ->
        @default_timezone
    end
  end

  @doc """
  Resolves the display metadata for one authenticated context.

  `user_scope` is the account's explicit Settings scope (or `nil` before
  authentication, which resolves to `:local` — the pre-policy behavior).
  `company_scope` supplies the company time zone for `:company` mode.
  Before the canonical Settings table exists, resolution returns defaults;
  every other database error stays visible.
  """
  @spec display(Scope.t() | nil, Scope.t() | nil) :: Display.t()
  def display(user_scope, company_scope \\ nil)

  def display(nil, _company_scope) do
    %Display{mode: :local, timezone: @default_timezone, tz_db: @tz_db}
  end

  def display(%Scope{type: :user} = user_scope, company_scope) do
    %Display{
      mode: mode(user_scope),
      timezone: company_timezone(company_scope),
      locale: Locale.resolve(user_scope).locale,
      tz_db: @tz_db
    }
  rescue
    error in Postgrex.Error ->
      if match?(%{postgres: %{code: :undefined_table}}, error) do
        %Display{mode: @default_mode, timezone: @default_timezone, tz_db: @tz_db}
      else
        reraise error, __STACKTRACE__
      end
  end

  @doc """
  Shifts a stored timestamp into a zone under the real database.

  Compatible `NaiveDateTime` values are explicitly interpreted as UTC.
  Returns `{:error, reason}` rather than guessing when the zone cannot
  convert.
  """
  @spec shift(DateTime.t() | NaiveDateTime.t(), String.t()) ::
          {:ok, DateTime.t()} | {:error, term()}
  def shift(%NaiveDateTime{} = value, timezone) do
    value |> DateTime.from_naive!("Etc/UTC") |> shift(timezone)
  end

  def shift(%DateTime{} = value, timezone) do
    DateTime.shift_zone(value, timezone, @tz_db)
  end

  defp parse_mode(mode) when mode in @modes, do: mode
  defp parse_mode("company"), do: :company
  defp parse_mode("local"), do: :local
  defp parse_mode("utc"), do: :utc
  defp parse_mode(_other), do: @default_mode
end
