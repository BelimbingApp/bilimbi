defmodule Bilimbi.Base.DateTime.Display do
  @moduledoc """
  Server-authorized timestamp display metadata for one request or LiveView.

  The web edge resolves this once from the authenticated context and hands it
  to presentation (`Bilimbi.Base.UI.DateTimeDisplay`). Client enhancement may
  use `Intl`, but only on top of this metadata — never on arbitrary DOM or
  request values.

  `timezone` is the company IANA identifier and only participates in
  `:company` mode; `tz_db` is the `Calendar.time_zone_database` the shift
  runs against, carried as a value so no presentation module needs a
  dependency on the database package.
  """

  @enforce_keys [:mode]
  defstruct mode: :local, timezone: "UTC", locale: nil, tz_db: nil

  @type mode :: :company | :local | :utc
  @type t :: %__MODULE__{
          mode: mode(),
          timezone: String.t(),
          locale: String.t() | nil,
          tz_db: module() | nil
        }
end
