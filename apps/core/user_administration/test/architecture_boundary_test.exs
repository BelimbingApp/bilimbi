defmodule Bilimbi.Core.UserAdministration.ArchitectureBoundaryTest do
  use ExUnit.Case, async: true

  alias Bilimbi.Core.UserAdministration.ArchitecturePolicy
  alias Bilimbi.Core.UserAdministration.ConsumedRelations

  @module_root Path.expand("..", __DIR__)
  @query_file Path.join(@module_root, "lib/user_administration/query.ex")

  test "the descriptor has the reviewed graph and only the transferred web route contribution" do
    {descriptor, _binding} = Code.eval_file(Path.join(@module_root, "bilimbi.module.exs"))

    assert descriptor == [
             id: "core/user_administration",
             kind: :module,
             layer: :core,
             required: true,
             otp_app: :bilimbi_core_user_administration,
             namespace: Bilimbi.Core.UserAdministration,
             dependencies: [
               "base/authz",
               "base/database",
               "base/module_registry",
               "base/tenancy",
               "base/ui",
               "core/company",
               "core/user"
             ],
             migrations: nil,
             web: "priv/web_routes.exs",
             schema_contract: nil,
             contribution_provider: nil
           ]
  end

  test "every product file satisfies the exact manifest-bound Query exception" do
    files = Path.wildcard(Path.join(@module_root, "lib/**/*.ex"))

    assert ArchitecturePolicy.validate_files(files, ConsumedRelations.manifest(), @query_file) ==
             []

    assert Enum.all?(ArchitecturePolicy.source_sites(files), fn site ->
             is_integer(site.meta[:line]) and site.meta[:line] > 0 and
               is_integer(site.meta[:column]) and site.meta[:column] > 0
           end)

    assert Enum.all?(ArchitecturePolicy.fragment_sites(files), fn site ->
             is_integer(site.meta[:line]) and site.meta[:line] > 0 and
               is_integer(site.meta[:column]) and site.meta[:column] > 0
           end)
  end

  test "alternate, fully-qualified, imported, and delegated Repo escapes fail" do
    mutations = [
      """
      defmodule Sneaky do
        alias Bilimbi.Base.Repo, as: Database
        def read(query), do: Database.all(query)
      end
      """,
      """
      defmodule Sneaky do
        def read(query), do: Bilimbi.Base.Repo.all(query)
      end
      """,
      """
      defmodule Sneaky do
        import Bilimbi.Base.Repo
        def read(query), do: all(query)
      end
      """,
      """
      defmodule Sneaky do
        defdelegate read(query), to: Bilimbi.Base.Repo, as: :all
      end
      """,
      ~S"""
      defmodule Sneaky do
        alias Bilimbi.Base.Repo
        def read(query), do: apply(Repo, :query!, [query])
      end
      """,
      ~S"""
      defmodule Sneaky do
        alias Bilimbi.Base.Repo
        def read(query), do: Kernel.apply(Repo, :query!, [query])
      end
      """,
      ~S"""
      defmodule Sneaky do
        def read(query), do: apply(Bilimbi.Base.Repo, :query!, [query])
      end
      """,
      ~S"""
      defmodule Sneaky do
        def read(query), do: Kernel.apply(Bilimbi.Base.Repo, :query!, [query])
      end
      """
    ]

    Enum.each(mutations, fn source ->
      assert violations(source) != []
    end)
  end

  test "approved Repo alias cannot escape through Kernel or unqualified apply" do
    mutations = [
      ~S|Kernel.apply(Repo, :query!, ["SELECT password FROM users"])|,
      ~S|apply(Repo, :query!, ["SELECT password FROM users"])|
    ]

    Enum.each(mutations, fn expression ->
      assert query_violations(expression)
             |> Enum.any?(&String.contains?(&1, "dynamic module dispatch"))
    end)

    full_module = """
    defmodule Sneaky do
      def read, do: Kernel.apply(Bilimbi.Base.Repo, :query!, ["SELECT password FROM users"])
    end
    """

    alternate_alias = """
    defmodule Sneaky do
      alias Bilimbi.Base.Repo, as: Database
      def read, do: apply(Database, :query!, ["SELECT password FROM users"])
    end
    """

    for source <- [full_module, alternate_alias] do
      assert Enum.any?(violations(source), &String.contains?(&1, "dynamic module dispatch"))
    end
  end

  test "computed apply targets and Module.concat construction fail closed" do
    dynamic_target = """
    defmodule Sneaky do
      def read(target, query), do: apply(target, :all, [query])
    end
    """

    constructed_target = """
    defmodule Sneaky do
      alias Module, as: Builder

      def read do
        target = Builder.concat([Bilimbi, Base, Repo])
        apply(target, :query!, ["SELECT password FROM users"])
      end
    end
    """

    assert Enum.any?(violations(dynamic_target), &String.contains?(&1, "dynamic module dispatch"))

    assert Enum.any?(
             violations(constructed_target),
             &String.contains?(&1, "target construction")
           )
  end

  test "Ecto.Query descendants and their aliases remain query infrastructure" do
    mutations = [
      ~S"""
      defmodule Sneaky do
        def read(role), do: Ecto.Query.API.fragment("SELECT * FROM users", role.id)
      end
      """,
      ~S"""
      defmodule Sneaky do
        alias Ecto.Query.API, as: QueryAPI
        def read(role), do: QueryAPI.fragment("SELECT * FROM users", role.id)
      end
      """
    ]

    Enum.each(mutations, fn source ->
      assert Enum.any?(violations(source), &String.contains?(&1, "Ecto.Query infrastructure"))
    end)
  end

  test "literal reviewed standard-library dispatch remains harmless" do
    source = """
    defmodule Harmless do
      def count(values), do: Kernel.apply(Enum, :count, [values])
    end
    """

    assert violations(source) == []
  end

  test "copied and dynamic Ecto sources outside the exact Query sites fail" do
    mutations = [
      """
      defmodule Sneaky do
        def read, do: from(user in "users", select: user.id)
      end
      """,
      """
      defmodule Sneaky do
        def read(source), do: from(user in source, select: user.id)
      end
      """,
      """
      defmodule Sneaky do
        def read, do: Ecto.Query.from(user in "companies", select: user.id)
      end
      """
    ]

    Enum.each(mutations, fn source ->
      assert Enum.any?(violations(source), &String.contains?(&1, "Ecto source"))
    end)
  end

  test "arbitrary, dynamic, wildcard, and extra-column fragments fail" do
    mutations = [
      ~S"""
      defmodule Sneaky do
        def read(role), do: fragment("SELECT * FROM users", role.id)
      end
      """,
      ~S"""
      defmodule Sneaky do
        def read(role), do: fragment("array_agg(? ORDER BY ?, ?, ?)", role.role_id, role.role_name, role.password, role.role_id)
      end
      """,
      ~S"""
      defmodule Sneaky do
        def read(sql, role), do: fragment(sql, role.role_id)
      end
      """
    ]

    Enum.each(mutations, fn source ->
      assert Enum.any?(violations(source), &String.contains?(&1, "fragment"))
    end)
  end

  test "owner schemas remain forbidden even without an alias declaration" do
    source = """
    defmodule Sneaky do
      def read(id), do: Bilimbi.Core.User.Schema.get(id)
    end
    """

    assert violations(source) != []
  end

  defp violations(source) do
    ArchitecturePolicy.validate_source(
      source,
      Path.join(@module_root, "lib/sneaky.ex"),
      ConsumedRelations.manifest(),
      @query_file
    )
  end

  defp query_violations(expression) do
    source = """
    defmodule Bilimbi.Core.UserAdministration.Query do
      @moduledoc false

      import Ecto.Query

      alias Bilimbi.Base.Repo
      def escape, do: #{expression}
    end
    """

    ArchitecturePolicy.validate_source(
      source,
      @query_file,
      ConsumedRelations.manifest(),
      @query_file
    )
  end
end
