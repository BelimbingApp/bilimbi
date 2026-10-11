defmodule Bilimbi.Base.Artifacts.PDF.Artifact do
  @moduledoc "PDF provenance plus a private Artifacts reference; never a filesystem path."
  alias Bilimbi.Base.Tenancy.Scope

  @enforce_keys [:document, :template_version, :data_version, :produced_by, :produced_at]
  defstruct @enforce_keys
  @type t :: %__MODULE__{}

  @doc false
  def new(document, scope, opts) do
    protected? = Keyword.get(opts, :password) not in [nil, ""]
    data_version = Keyword.get(opts, :data_version, "spike")

    %__MODULE__{
      document: document,
      template_version: Keyword.get(opts, :template_version, "spike"),
      data_version: if(protected?, do: data_version <> " (encrypted)", else: data_version),
      produced_by: Scope.actor(scope).user_id,
      produced_at: DateTime.utc_now()
    }
  end

  @doc "Serializes provenance without private paths or credentials."
  def to_map(%__MODULE__{} = artifact) do
    %{
      artifact_id: artifact.document.id,
      template_version: artifact.template_version,
      data_version: artifact.data_version,
      bytes: artifact.document.byte_size,
      sha256: artifact.document.sha256,
      produced_by: artifact.produced_by,
      produced_at: DateTime.to_iso8601(artifact.produced_at)
    }
  end
end
