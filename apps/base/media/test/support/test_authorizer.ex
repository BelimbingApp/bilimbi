defmodule Bilimbi.Base.Media.TestAuthorizer do
  @moduledoc false
  @behaviour Bilimbi.Base.Media.AttachmentSubjectAuthorizer
  alias Bilimbi.Base.Tenancy.Scope

  @impl true
  def authorize(scope, action, id, attachments) do
    send(self(), {:authorize, action, Scope.tenant_id(scope), id, attachments})

    cond do
      Scope.tenant_id(scope) != 41 -> {:error, :wrong_tenant}
      id not in ["1", "2"] -> {:error, :subject_not_found}
      Process.get({:deny_media, action}, false) -> {:error, :forbidden}
      true -> :ok
    end
  end
end
