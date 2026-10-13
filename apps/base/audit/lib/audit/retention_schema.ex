defmodule Bilimbi.Base.Audit.RetentionSchema do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:action_id, :id, autogenerate: false}
  schema "base_audit_action_metadata" do
    field :is_retained, :boolean, default: false
  end
end
