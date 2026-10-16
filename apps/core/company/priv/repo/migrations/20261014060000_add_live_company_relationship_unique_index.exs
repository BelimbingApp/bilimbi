defmodule Bilimbi.Core.Company.Migrations.AddLiveCompanyRelationshipUniqueIndex do
  @moduledoc false

  # `company_relationship_unique` includes the nullable `effective_from`, and
  # PostgreSQL treats NULLs as distinct, so an undated link could be assigned
  # twice. One open-ended live link per source, target and role is the rule;
  # an ended (`effective_to` set) or unlinked (`deleted_at` set) row stays as
  # history and does not block a later role of the same type.
  #
  # A database that already holds duplicates keeps the link an external
  # access points at (else the oldest) and unlinks the others the way the
  # product does, with `deleted_at`; no row is removed.
  use Ecto.Migration

  alias Bilimbi.Base.Database.SchemaVerifier

  def up do
    schema = SchemaVerifier.quote_identifier!(prefix() || "public")

    execute("""
    UPDATE #{schema}.company_relationships AS dup
    SET deleted_at = (NOW() AT TIME ZONE 'UTC')::timestamp(0)
    WHERE dup.deleted_at IS NULL
      AND dup.effective_to IS NULL
      AND dup.id NOT IN (
        SELECT DISTINCT ON (live.company_id, live.related_company_id, live.relationship_type_id)
               live.id
        FROM #{schema}.company_relationships AS live
        WHERE live.deleted_at IS NULL AND live.effective_to IS NULL
        ORDER BY live.company_id,
                 live.related_company_id,
                 live.relationship_type_id,
                 EXISTS (
                   SELECT 1 FROM #{schema}.company_external_accesses AS access
                   WHERE access.relationship_id = live.id
                 ) DESC,
                 live.id
      )
    """)

    create(
      unique_index(
        :company_relationships,
        [
          :company_id,
          :related_company_id,
          :relationship_type_id
        ],
        where: "deleted_at IS NULL AND effective_to IS NULL",
        name: :company_relationship_live_unique
      )
    )
  end

  # Unlinked duplicates stay unlinked: they were history by then.
  def down do
    drop_if_exists(
      unique_index(
        :company_relationships,
        [:company_id, :related_company_id, :relationship_type_id],
        name: :company_relationship_live_unique
      )
    )
  end
end
