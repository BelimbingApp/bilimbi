defmodule Bilimbi.Base.AgentApi.Guide do
  @moduledoc """
  Short text a module registered to teach an agent its area: what a record
  means here, how its statuses move, which operations answer common tasks.

  A guide is found through search like an operation and read only by a
  scope holding its `capability`. Its `body` is Markdown of at most 8 KB.
  An operation's related guides are the guides whose key is a prefix of
  the operation's key (`core.company` for `core.company.get`).
  """

  @enforce_keys [:key, :owner, :title, :summary, :keywords, :capability, :body]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          key: String.t(),
          owner: String.t(),
          title: String.t(),
          summary: String.t(),
          keywords: [String.t()],
          capability: String.t(),
          body: String.t()
        }
end
