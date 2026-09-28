defmodule Bilimbi.Base.Settings.SecretRevealService do
  @moduledoc """
  Host integration for reauthenticating before a stored encrypted setting is shown.

  Base Settings owns the screen and setting scope; the Web host owns the
  credential check, rate limit, and request audit integration. The host returns
  a value only after those checks and an audit action succeed.
  """

  alias Bilimbi.Base.Settings.Scope

  @callback available?(map()) :: boolean()
  @callback reveal(map(), String.t(), Scope.t() | nil, String.t()) ::
              {:ok, String.t()} | {:error, atom()}
end
