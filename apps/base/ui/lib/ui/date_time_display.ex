defmodule Bilimbi.Base.UI.DateTimeDisplay do
  @moduledoc """
  Per-process timestamp display context, the `Gettext.put_locale/2` pattern.

  The web edge resolves the server-authorized display metadata (mode,
  company IANA time zone, time zone database module, locale) from the
  authenticated context and stores it here; `<.datetime>` reads it so every
  call site on a screen renders in the same mode without threading assigns.

  Base UI owns only this generic holder — the policy that fills it lives in
  `base/datetime`, keeping DateTime behavior out of Base UI's dependencies
  (#459). HTTP requests and LiveViews each set it in their own process, so
  no user's display context leaks into another request or LiveView process.

  The stored value is a plain map/struct with `:mode` (`:company | :local |
  :utc`), `:timezone`, and `:tz_db` (a `Calendar.time_zone_database` module
  passed as a value). Nothing stored means `:local` — the pre-policy
  behavior.
  """

  @key __MODULE__

  @spec put(map() | nil) :: :ok
  def put(nil) do
    Process.delete(@key)
    :ok
  end

  def put(%{mode: _mode} = display) do
    Process.put(@key, display)
    :ok
  end

  @spec get() :: map() | nil
  def get, do: Process.get(@key)
end
