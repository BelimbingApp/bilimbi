defmodule Bilimbi.Base.Queue.Migrations.CreateObanRuntime do
  use Ecto.Migration

  def up, do: Oban.Migration.up(migration_options(14))
  def down, do: Oban.Migration.down(migration_options(1))

  defp migration_options(version) do
    case prefix() do
      nil -> [version: version]
      migration_prefix -> [version: version, prefix: migration_prefix]
    end
  end
end
