defmodule Bilimbi.Core.Employee.Web.RouterTest do
  use ExUnit.Case, async: true

  alias Bilimbi.Core.Employee.Web.Router

  test "declares company-scoped employee and type screens" do
    # Embed entries (module-contributed panels) carry no `:path`; this test is
    # about the path-routed screens, so filter them out before keying by path.
    by_path =
      Router.routes()
      |> Enum.filter(&Map.has_key?(&1, :path))
      |> Map.new(&{&1.path, &1})

    assert by_path["/employees"].live == Bilimbi.Core.Employee.Web.IndexLive
    assert by_path["/employees"].capability == "admin.employee.list"

    assert by_path["/employees/new"].live == Bilimbi.Core.Employee.Web.FormLive
    assert by_path["/employees/new"].capability == "admin.employee.create"

    assert by_path["/employees/:id"].live == Bilimbi.Core.Employee.Web.ShowLive
    assert by_path["/employees/:id"].capability == "admin.employee.view"

    assert by_path["/employee-types"].live == Bilimbi.Core.Employee.Web.TypeIndexLive
    assert by_path["/employee-types"].capability == "admin.employee-type.list"

    assert by_path["/employee-types/new"].live == Bilimbi.Core.Employee.Web.TypeFormLive
    assert by_path["/employee-types/new"].capability == "admin.employee-type.create"

    assert by_path["/employee-types/:id"].live == Bilimbi.Core.Employee.Web.TypeShowLive
    assert by_path["/employee-types/:id"].capability == "admin.employee-type.list"
  end

  test "a record's page edits in place, so no separate edit route is declared" do
    # `/employees/:id` and `/employee-types/:id` are read-first: every fact
    # an operator may change commits on the record's page, so an edit form
    # for the same facts would be a second surface for one workflow.
    paths = Router.routes() |> Enum.filter(&Map.has_key?(&1, :path)) |> Enum.map(& &1.path)

    refute "/employees/:id/edit" in paths
    refute "/employee-types/:id/edit" in paths
    refute Enum.any?(paths, &String.ends_with?(&1, "/edit"))
  end

  test "employee form account linking goes through the discovered seam" do
    source =
      Path.expand("../lib/employee/web/form_live.ex", __DIR__)
      |> File.read!()

    assert source =~ "DiscoveredPanels.dispatch(\"employee.accounts\", :employee_account_options"
    assert source =~ "DiscoveredPanels.dispatch(\"employee.accounts\", :replace_employee_account"

    refute source =~ ~S|Module.concat(["Bilimbi", "Core", "User"])|
    refute source =~ "Code.ensure_loaded?"
    refute source =~ "function_exported?"
    refute source =~ "apply(user_mod"
  end
end
