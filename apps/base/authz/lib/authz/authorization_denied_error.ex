defmodule Bilimbi.Base.Authz.AuthorizationDeniedError do
  @moduledoc "Raised by `Bilimbi.Base.Authz.authorize!/4` for a denied decision."

  defexception [:decision, message: "authorization denied"]

  @impl true
  def exception(opts) do
    decision = Keyword.fetch!(opts, :decision)

    %__MODULE__{
      decision: decision,
      message: "authorization denied: #{decision.reason}"
    }
  end
end
