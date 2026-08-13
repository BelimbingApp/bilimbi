defmodule Bilimbi.Base.Audit.Mutation do
  @moduledoc """
  Stable read model for a recorded data mutation.

  Callers receive this struct, never the private Ecto schema.
  """

  alias Bilimbi.Base.Audit.MutationSchema

  @enforce_keys [
    :id,
    :actor_type,
    :actor_id,
    :auditable_type,
    :auditable_id,
    :event,
    :occurred_at
  ]
  defstruct [
    :id,
    :company_id,
    :tenant_id,
    :actor_type,
    :actor_id,
    :actor_role,
    :ip_address,
    :url,
    :user_agent,
    :auditable_type,
    :auditable_id,
    :subject_name,
    :subject_id,
    :subject_identifier,
    :source,
    :event,
    :old_values,
    :new_values,
    :trace_id,
    :occurred_at
  ]

  @type t :: %__MODULE__{
          id: pos_integer(),
          company_id: pos_integer() | nil,
          tenant_id: pos_integer() | nil,
          actor_type: String.t(),
          actor_id: integer(),
          actor_role: String.t() | nil,
          ip_address: Postgrex.INET.t() | nil,
          url: String.t() | nil,
          user_agent: String.t() | nil,
          auditable_type: String.t(),
          auditable_id: String.t(),
          subject_name: String.t() | nil,
          subject_id: String.t() | nil,
          subject_identifier: String.t() | nil,
          source: String.t(),
          event: String.t(),
          old_values: map() | list() | nil,
          new_values: map() | list() | nil,
          trace_id: String.t() | nil,
          occurred_at: NaiveDateTime.t()
        }

  @doc false
  @spec from_schema(MutationSchema.t()) :: t()
  def from_schema(%MutationSchema{} = mutation) do
    %__MODULE__{
      id: mutation.id,
      company_id: mutation.company_id,
      tenant_id: mutation.tenant_id,
      actor_type: mutation.actor_type,
      actor_id: mutation.actor_id,
      actor_role: mutation.actor_role,
      ip_address: mutation.ip_address,
      url: mutation.url,
      user_agent: mutation.user_agent,
      auditable_type: mutation.auditable_type,
      auditable_id: mutation.auditable_id,
      subject_name: mutation.subject_name,
      subject_id: mutation.subject_id,
      subject_identifier: mutation.subject_identifier,
      source: mutation.source,
      event: mutation.event,
      old_values: mutation.old_values,
      new_values: mutation.new_values,
      trace_id: mutation.trace_id,
      occurred_at: mutation.occurred_at
    }
  end
end
