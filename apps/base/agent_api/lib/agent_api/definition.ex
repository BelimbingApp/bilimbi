defmodule Bilimbi.Base.AgentApi.Definition do
  @moduledoc """
  One operation a module registered, as the validator accepted it.

  `owner` is the stable id of the module that declared it. `capability` is
  the key the matching screen's route or event asks for, and the dispatcher
  asks it again on every call. `approval` is `nil` for a read and `:level`
  or `:required` for a write. `input` is an
  `Bilimbi.Base.AgentApi.InputSchema` object; `output` describes the result
  for an agent and is not enforced.
  """

  @enforce_keys [
    :key,
    :owner,
    :title,
    :summary,
    :keywords,
    :kind,
    :capability,
    :approval,
    :input,
    :output,
    :handler
  ]
  defstruct @enforce_keys

  @type kind :: :read | :write

  @type t :: %__MODULE__{
          key: String.t(),
          owner: String.t(),
          title: String.t(),
          summary: String.t(),
          keywords: [String.t()],
          kind: kind(),
          capability: String.t(),
          approval: nil | :level | :required,
          input: map(),
          output: map(),
          handler: module()
        }
end
