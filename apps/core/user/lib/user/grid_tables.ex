defmodule Bilimbi.Core.User.GridTables do
  @moduledoc """
  What Core User puts in the grid catalog: the `users` table, its link to
  the company and employee a user is affiliated with, and the inbound
  many-links from those tables back to their users. Core User depends on
  Core Company and Core Employee, so it is the module that may name their
  tables.
  """

  alias Bilimbi.Core.User.Grid.UsersSource

  @doc false
  def tables do
    %{
      tables: [
        %{
          id: "users",
          record_kind: "core/user",
          label: "Users",
          capability: "admin.user.list",
          source: UsersSource,
          key: "id",
          label_field: "name",
          time_field: "created_at",
          fields: [
            %{id: "id", label: "ID", type: :integer},
            %{id: "name", label: "Name", type: :string},
            %{id: "email", label: "Email", type: :string},
            %{id: "email_verified_at", label: "Email verified", type: :datetime},
            %{id: "created_at", label: "Created", type: :datetime},
            %{id: "updated_at", label: "Updated", type: :datetime},
            %{id: "company_id", type: :integer, hidden: true},
            %{id: "employee_id", type: :integer, hidden: true}
          ],
          links: [
            %{
              id: "company",
              label: "Company",
              to: "companies",
              kind: :one,
              on: {"company_id", "id"}
            },
            %{
              id: "employee",
              label: "Employee",
              to: "employees",
              kind: :one,
              on: {"employee_id", "id"}
            },
            %{
              id: "users",
              label: "Users",
              from: "companies",
              to: "users",
              kind: :many,
              on: {"id", "company_id"}
            },
            %{
              id: "users",
              label: "Users",
              from: "employees",
              to: "users",
              kind: :many,
              on: {"id", "employee_id"}
            }
          ]
        }
      ]
    }
  end
end
