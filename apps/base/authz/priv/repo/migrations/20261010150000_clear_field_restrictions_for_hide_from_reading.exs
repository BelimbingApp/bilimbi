defmodule Bilimbi.Base.Authz.Migrations.ClearFieldRestrictionsForHideFromReading do
  @moduledoc """
  Bilimbi-only: the stored meaning of a field restriction's roles flipped.

  Until now a restriction's roles were the roles that could still see the
  field. From now on they are the roles the field is restricted for: every
  field is visible by default, and only holders of a named role read it as
  Restricted. A row written under the old meaning would, read the new way,
  hide the field from exactly the people it was meant to show it to and
  show it to everyone else, so no row is kept. The operator restricts again
  on Administration › Authorization › Field Restrictions; the retained
  `authz.field_restriction.set` audit actions keep the history of what was
  restricted before. No production database carries these rows: the tables
  are Bilimbi-only and days old.

  Raw DML, deliberately: a migration runs before the application and its
  audit capture, and the rows it removes are the ones the audit log already
  names.
  """

  use Ecto.Migration

  def up do
    execute("DELETE FROM base_authz_field_restriction_roles")
    execute("DELETE FROM base_authz_field_restrictions")
  end

  def down do
    :ok
  end
end
