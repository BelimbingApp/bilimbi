defmodule Bilimbi.Core.User.BootstrapReceipt do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :id, autogenerate: false}
  schema "bilimbi_user_bootstrap" do
    field(:tenant_name, :string)
    field(:company_name, :string)
    field(:company_code, :string)
    field(:admin_email, :string)
    field(:user_id, :id)
    field(:company_id, :id)
    field(:tenant_id, :id)
    field(:completed_at, :naive_datetime)
  end
end
