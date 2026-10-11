defmodule Bilimbi.Base.Artifacts.PDF.Rendered do
  @moduledoc "Queued PDF completion fact. Contains routing metadata, never input data or passwords."
  @enforce_keys [:request_id, :job_id, :artifact, :metadata]
  defstruct @enforce_keys
  @type t :: %__MODULE__{}
end
