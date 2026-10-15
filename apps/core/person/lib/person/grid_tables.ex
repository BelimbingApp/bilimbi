defmodule Bilimbi.Core.Person.GridTables do
  @moduledoc "Core identity, affiliation and role field access policy, including audit read models."
  def tables do
    %{
      tables: [
        %{
          id: "core_people",
          label: "Contacts",
          capability: "admin.person.list",
          source: Bilimbi.Core.Person.Grid.PeopleSource,
          key: "id",
          label_field: "full_name",
          time_field: "created_at",
          record_types: ["Bilimbi.Core.Person.Schema"],
          fields: [
            %{id: "id", type: :integer},
            %{id: "full_name", label: "Name", type: :string},
            %{id: "email", label: "Email", type: :string},
            %{id: "phone", label: "Phone", type: :string},
            %{id: "created_at", type: :datetime},
            %{id: "retired_at", type: :datetime, protected: true}
          ],
          links: []
        },
        %{
          id: "core_person_affiliations",
          label: "Person affiliations",
          capability: "admin.person.view",
          source: Bilimbi.Core.Person.Grid.AffiliationsSource,
          key: "id",
          label_field: "id",
          time_field: "created_at",
          record_types: ["Bilimbi.Core.Person.Affiliation"],
          fields: [
            %{id: "id", type: :integer},
            %{id: "title", label: "Title", type: :string},
            %{id: "email", label: "Email", type: :string},
            %{id: "phone", label: "Phone", type: :string},
            %{id: "person_id", type: :integer, protected: true},
            %{id: "company_id", type: :integer, protected: true},
            %{id: "legacy_employee_id", type: :integer, protected: true},
            %{id: "created_at", type: :datetime},
            %{id: "unlinked_at", type: :datetime, protected: true}
          ],
          links: []
        },
        %{
          id: "core_person_relationships",
          label: "Person roles",
          capability: "admin.person.view",
          source: Bilimbi.Core.Person.Grid.RelationshipsSource,
          key: "id",
          label_field: "id",
          time_field: "created_at",
          record_types: ["Bilimbi.Core.Person.Relationship"],
          fields: [
            %{id: "id", type: :integer},
            %{id: "effective_from", label: "Effective from", type: :date},
            %{id: "effective_to", label: "Effective to", type: :date},
            %{id: "person_id", type: :integer, protected: true},
            %{id: "company_id", type: :integer, protected: true},
            %{id: "relationship_type_id", type: :integer, protected: true},
            %{id: "created_at", type: :datetime},
            %{id: "deleted_at", type: :datetime, protected: true}
          ],
          links: []
        }
      ]
    }
  end
end
