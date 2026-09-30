defmodule Bilimbi.Base.Artifacts.TestOwner do
  @moduledoc false
  @behaviour Bilimbi.Base.Artifacts.Owner
  @behaviour Bilimbi.Base.Artifacts.PDF

  @impl true
  def artifact_owner_id, do: "test/documents"

  @impl true
  def authorize(scope, company, operation, ref) do
    send(self(), {:authorized, operation, company, ref})
    create_count = Process.get(:create_count, 0) + if(operation == :create, do: 1, else: 0)
    Process.put(:create_count, create_count)
    deny_after = Process.get(:deny_create_after)

    publication_denied? =
      operation == :create and is_integer(deny_after) and create_count > deny_after

    if Bilimbi.Base.Tenancy.Scope.tenant_id(scope) == 41 and company in [51, 52] and
         not Process.get({:deny, operation}, false) and not publication_denied?,
       do: :ok,
       else: {:error, :forbidden}
  end

  @impl true
  def render_pdf(_scope, _company, _ref, data) do
    send(self(), :rendered)
    {:ok, Map.get(data, :pdf, "%PDF-1.7\n%%EOF")}
  end
end
