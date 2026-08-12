defmodule Bilimbi.Base.Database.SchemaContract do
  @moduledoc """
  Contract implemented by modules that contribute compatible database schema.

  Structural table specifications are required. Data invariants are optional
  and remain owned by the module that understands their business meaning.
  """

  alias Bilimbi.Base.Database.SchemaVerifier

  @callback tables() :: [SchemaVerifier.table_spec()]
  @callback verify_invariants(Ecto.Repo.t(), keyword()) :: :ok | {:error, [String.t()]}

  @optional_callbacks verify_invariants: 2
end
