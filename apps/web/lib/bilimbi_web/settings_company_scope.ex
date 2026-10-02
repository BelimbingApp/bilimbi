defmodule BilimbiWeb.SettingsCompanyScope do
  @moduledoc "Host authorization for company-scoped operator settings."
  @behaviour Bilimbi.Base.Settings.CompanyScopeService

  alias Bilimbi.Base.Authz.Actor
  alias Bilimbi.Base.Settings.Scope, as: SettingScope
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.Company

  @capability "base.settings.company.manage"

  @impl true
  def companies(%{actor: %Actor{} = actor}) do
    case Company.list_selectable_companies(actor, @capability) do
      {:ok, companies} -> Enum.map(companies, &%{id: &1.id, name: &1.name})
      {:error, _} -> []
    end
  end

  @impl true
  def authorize(%{scope: %Scope{} = scope, actor: %Actor{} = actor}, id) do
    with {:ok, company} <-
           Company.authorize_company_target(actor, id, @capability) do
      {:ok, SettingScope.company(company.id, Scope.tenant_id(scope))}
    end
  end
end
