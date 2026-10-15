defmodule Bilimbi.Core.Person.Contributions do
  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider
  @capabilities ~w(admin.person.list admin.person.view admin.person.create admin.person.update)
  @impl true
  def contributions do
    %{
      grid: Bilimbi.Core.Person.GridTables.tables(),
      menu: [
        %{
          id: "admin.contacts",
          label: "Contacts",
          icon: "user-group",
          parent: "admin",
          route: "/contacts",
          capability: "admin.person.list",
          order: 15
        }
      ],
      authz: %{
        capabilities: @capabilities,
        roles: %{"tenant_owner" => %{capabilities: @capabilities}}
      },
      agent_api: %{
        operations: Bilimbi.Core.Person.AgentOperations.declarations(),
        guides: [
          %{
            key: "core.person",
            title: "Contacts and affiliations",
            summary: "Namecard contacts without HR or account grants.",
            keywords: ~w(namecard vendor contact person),
            capability: "admin.person.list",
            body: """
            Search core.company.list and core.person.list for duplicates first.
            Create or reuse the company. Assign roles through core.company.relationship.create.
            The related company is the named role toward the source; vendor means it supplies
            the source. Customer and vendor can coexist as separate links. Roles grant no access.
            Create a new person and affiliation with core.person.contact.create (full_name,
            company_id, optional title/email/phone). For an existing person, use
            core.person.affiliation.link. Personal contact details use core.person.update;
            company-specific details use core.person.affiliation.update. Unlink and retire
            preserve history and never terminate employment or revoke account grants.
            These writes require preview, review/approval, and exact plan-code commit.
            A person can hold a role toward a company too (individual customer, prospect or
            lead): core.person.relationship.create with person_id, company_id and a role from
            core.company.relationship_role.list; the person is the role toward that company.
            A prospect becomes a customer by core.person.relationship.unlink (or an
            effective_to date) on the prospect role and a create for the customer role;
            history is kept. A role targets exactly one company or one person.
            Do not invent employee numbers, employment type/status or a login from a namecard.
            core.employee.* is deprecated HR compatibility, reserved for confirmed HR records.
            People will own employment facts and reference this same core identity/affiliation.
            """
          }
        ]
      }
    }
  end
end
