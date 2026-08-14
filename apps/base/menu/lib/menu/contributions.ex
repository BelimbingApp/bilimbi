defmodule Bilimbi.Base.Menu.Contributions do
  @moduledoc """
  The structural roots Base Menu owns, mirroring Belimbing's
  `app/Base/Menu/Config/menu.php`.

  These carry no route and no capability: they are grouping containers, and
  `Bilimbi.Base.Menu.visible_tree/1` hides any container that ends up with no
  visible child. That is what keeps a section out of the navigation until a
  module contributes something under it — including the Domain roots below,
  which stay hidden until their Domains are installed.
  """

  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider

  @impl true
  def contributions do
    %{menu: admin_roots() ++ domain_roots()}
  end

  # Ids, labels and parents are Belimbing's, unchanged.
  defp admin_roots do
    [
      %{id: "admin", label: "Administration", icon: "cog-6-tooth", order: 900},
      %{id: "admin.system", label: "System", parent: "admin", order: 90},
      %{id: "admin.system.database", label: "Database", parent: "admin.system", order: 10},
      %{
        id: "admin.system.diagnostics",
        label: "Diagnostics",
        parent: "admin.system",
        order: 20
      },
      %{
        id: "admin.system.integrations",
        label: "Integrations",
        parent: "admin.system",
        order: 30
      },
      %{id: "admin.system.software", label: "Software", parent: "admin.system", order: 40}
    ]
  end

  # Belimbing declares these in Base/Menu rather than in the Domains, so a
  # Domain's own items have a parent to attach to. They stay invisible here
  # until a Domain contributes a child, because no Domain is installed yet.
  defp domain_roots do
    [
      %{id: "finance", label: "Finance", order: 400},
      %{id: "maintenance", label: "Maintenance", order: 500},
      %{id: "procurement", label: "Procurement", order: 300},
      %{id: "production", label: "Production", order: 200}
    ]
  end
end
