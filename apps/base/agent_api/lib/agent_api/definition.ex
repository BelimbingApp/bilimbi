defmodule Bilimbi.Base.AgentApi.Definition do
  @moduledoc """
  One operation a module registered, as the validator accepted it.

  `owner` is the stable id of the module that declared it. `capability` is
  the key the matching screen's route or event asks for, and the dispatcher
  asks it again on preview and commit. `safe_write: true` declares the
  preview/commit contract; a plan code gates the write (ADR 0021). `input` is an
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
    :input,
    :output,
    :handler
  ]
  defstruct @enforce_keys ++ [safe_write: false]

  @type kind :: :read | :write

  @type t :: %__MODULE__{
          key: String.t(),
          owner: String.t(),
          title: String.t(),
          summary: String.t(),
          keywords: [String.t()],
          kind: kind(),
          capability: String.t(),
          input: map(),
          output: map(),
          handler: module(),
          safe_write: boolean()
        }
end
