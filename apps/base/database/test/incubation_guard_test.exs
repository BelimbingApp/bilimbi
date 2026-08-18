defmodule Bilimbi.Base.Database.IncubationGuardTest do
  @moduledoc """
  Bilimbi migrates forward. It does not incubate schema.

  Belimbing lets a migration stay editable in place during local development
  (`App\\Base\\Database\\Concerns\\IncubatingSchema`, `migrate --dev`, an
  incubating-schema preflight, and a migration-source ledger to track which
  migrations are still incubating). @kiatng ruled that mechanism out for
  Bilimbi: every schema change is a new migration, never an edit to one already
  applied (#327).

  That extends a rejection #90 had already made -- *"Laravel table/migration-source
  registries must not be adopted beside `bilimbi_schema_migrations`"* -- since
  those registries exist to serve incubation.

  This test exists because of #90's own rationale: **an unrecorded rejection gets
  re-proposed, and that had already happened once.** A capability named
  `admin.system.database-incubation.manage` sat in the declared catalogue wired
  to nothing, which reads to the next reader as a planned feature rather than a
  rejected one.

  Derived rather than a fixture: it reads the contribution sources, so it cannot
  pass by being edited alongside the thing it guards -- #201's failure mode.
  """

  use ExUnit.Case, async: true

  @workspace_root Path.expand("../../../..", __DIR__)

  test "no module declares an incubation capability" do
    offenders =
      @workspace_root
      |> Path.join("apps/*/*/lib/**/contributions.ex")
      |> Path.wildcard()
      |> Enum.flat_map(&incubation_lines/1)
      |> Enum.sort()

    assert offenders == [],
           """
           Bilimbi uses forward migration only; table incubation is ported as nothing (#327).

           Declared here:
           #{Enum.map_join(offenders, "\n", &("  " <> &1))}
           """
  end

  defp incubation_lines(path) do
    relative = Path.relative_to(path, @workspace_root)

    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.filter(fn {line, _number} -> String.contains?(String.downcase(line), "incubat") end)
    |> Enum.map(fn {line, number} -> "#{relative}:#{number} #{String.trim(line)}" end)
  end
end
