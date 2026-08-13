defmodule Bilimbi.Core.Company.ExternalAccessSummary do
  @moduledoc "Public read model for a company-granted external access."

  alias Bilimbi.Core.Company.ExternalAccess

  @fields [
    :id,
    :company_id,
    :relationship_id,
    :user_id,
    :permissions,
    :is_active,
    :access_granted_at,
    :access_expires_at,
    :metadata,
    :created_at,
    :updated_at
  ]

  @enforce_keys [:id, :company_id, :relationship_id, :is_active]
  defstruct @fields

  @type t :: %__MODULE__{
          id: pos_integer(),
          company_id: pos_integer(),
          relationship_id: pos_integer(),
          user_id: pos_integer() | nil,
          permissions: term(),
          is_active: boolean(),
          access_granted_at: NaiveDateTime.t() | nil,
          access_expires_at: NaiveDateTime.t() | nil,
          metadata: term(),
          created_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  @spec from_schema(ExternalAccess.t()) :: t()
  def from_schema(access) do
    struct!(__MODULE__, Map.from_struct(access) |> Map.take(@fields))
  end

  @doc """
  Whether the access is currently usable: active, granted (if dated), and
  not expired. Matches Belimbing `ExternalAccess::isValid()`.
  """
  @spec valid?(t(), NaiveDateTime.t()) :: boolean()
  def valid?(%__MODULE__{} = access, now \\ NaiveDateTime.utc_now()) do
    cond do
      not access.is_active ->
        false

      match?(%NaiveDateTime{}, access.access_granted_at) and
          NaiveDateTime.compare(access.access_granted_at, now) == :gt ->
        false

      match?(%NaiveDateTime{}, access.access_expires_at) and
          NaiveDateTime.compare(access.access_expires_at, now) == :lt ->
        false

      true ->
        true
    end
  end
end
