defmodule Bilimbi.Core.Employee.Web.RouterTest do
  use ExUnit.Case, async: true

  alias Bilimbi.Core.Employee.Web.Router

  test "declares company-scoped employee and type screens" do
    by_path = Map.new(Router.routes(), &{&1.path, &1})

    assert by_path["/employees"].live == Bilimbi.Core.Employee.Web.IndexLive
    assert by_path["/employees"].capability == "admin.employee.list"

    assert by_path["/employees/new"].live == Bilimbi.Core.Employee.Web.FormLive
    assert by_path["/employees/new"].capability == "admin.employee.create"

    assert by_path["/employees/:id"].live == Bilimbi.Core.Employee.Web.ShowLive
    assert by_path["/employees/:id"].capability == "admin.employee.view"

    assert by_path["/employees/:id/edit"].live == Bilimbi.Core.Employee.Web.FormLive
    assert by_path["/employees/:id/edit"].capability == "admin.employee.update"

    assert by_path["/employee-types"].live == Bilimbi.Core.Employee.Web.TypeIndexLive
    assert by_path["/employee-types"].capability == "admin.employee-type.list"

    assert by_path["/employee-types/new"].live == Bilimbi.Core.Employee.Web.TypeFormLive
    assert by_path["/employee-types/new"].capability == "admin.employee-type.create"
  end
end
