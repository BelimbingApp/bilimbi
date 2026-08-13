defmodule Bilimbi.Base.Authz.DecisionLogger do
  @moduledoc "Swappable side-effect boundary for authorization decision persistence."

  alias Bilimbi.Base.Authz.Actor
  alias Bilimbi.Base.Authz.Decision
  alias Bilimbi.Base.Authz.Resource

  @callback log(Actor.t(), String.t(), Resource.t() | nil, Decision.t(), map()) :: :ok
end
