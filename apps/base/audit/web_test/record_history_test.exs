defmodule Bilimbi.Base.Audit.Web.RecordHistoryTest do
  @moduledoc """
  The record history panel's own rendering: a stored timestamp inside a diff
  shows in the page's clock, whatever field carried it, and values that do
  not denote an instant stay text.
  """

  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Audit
  alias Bilimbi.Base.Audit.TestFixtures, as: AuditFixtures
  alias Bilimbi.Base.Audit.Web.RecordHistory
  alias Bilimbi.Base.DateTime, as: DateTimePolicy
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.UI.DateTimeDisplay
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures

  # 10:00 UTC is 18:00 the same day in Asia/Kuala_Lumpur.
  @company_text "18/08/2026, 18:00 +08"

  setup do
    AuditFixtures.create_audit_tables!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})
    {:ok, scope} = Tenancy.scope(41)

    DateTimeDisplay.put(%{
      mode: :company,
      timezone: "Asia/Kuala_Lumpur",
      tz_db: DateTimePolicy.time_zone_database()
    })

    on_exit(fn -> DateTimeDisplay.put(nil) end)

    %{scope: scope}
  end

  test "renders every stored timestamp in the display zone, recognised by shape", %{
    scope: scope
  } do
    {:ok, mutation} =
      Audit.record_mutation(scope, %{
        company_id: 73,
        actor_type: "user",
        actor_id: 91,
        auditable_type: "Bilimbi.Core.Widget.Schema",
        auditable_id: "7",
        event: "created",
        occurred_at: ~N[2026-08-18 10:00:00],
        old_values: %{},
        new_values: %{
          "name" => "Widget",
          "created_at" => "2026-08-18T10:00:00",
          "archived_at" => "2026-08-18 10:00:00",
          "synced_at" => "2026-08-18T18:00:00+08:00",
          "born_on" => "2026-08-18",
          "opens_at" => "10:00:00"
        }
      })

    html = render_panel(scope, mutation)

    # The entry's own time and the timestamps inside its diff agree: same
    # instant, same clock, and the zone is named on each.
    assert text(html, "time#history-entry-#{mutation.id}-occurred") == @company_text
    assert text(html, "time#history-entry-#{mutation.id}-created_at-new") == @company_text
    assert text(html, "time#history-entry-#{mutation.id}-archived_at-new") == @company_text
    assert text(html, "time#history-entry-#{mutation.id}-synced_at-new") == @company_text
    refute text(html, "#history-panel") =~ "2026-08-18T10:00:00"

    # A calendar date and a bare time denote no instant and stay as stored.
    assert text(html, "span#history-entry-#{mutation.id}-born_on-new") == "2026-08-18"
    assert text(html, "span#history-entry-#{mutation.id}-opens_at-new") == "10:00:00"
    assert text(html, "span#history-entry-#{mutation.id}-name-new") == "Widget"
  end

  test "an update shows both sides of a moved timestamp in the display zone", %{scope: scope} do
    {:ok, mutation} =
      Audit.record_mutation(scope, %{
        company_id: 73,
        actor_type: "user",
        actor_id: 91,
        auditable_type: "Bilimbi.Core.Widget.Schema",
        auditable_id: "7",
        event: "updated",
        occurred_at: ~N[2026-08-18 10:00:00],
        old_values: %{"expires_at" => "2026-08-18T10:00:00"},
        new_values: %{"expires_at" => "2026-08-19T10:00:00"}
      })

    html = render_panel(scope, mutation)

    assert text(html, "time#history-entry-#{mutation.id}-expires_at-old") == @company_text

    assert text(html, "time#history-entry-#{mutation.id}-expires_at-new") ==
             "19/08/2026, 18:00 +08"
  end

  defp render_panel(scope, mutation) do
    render_component(RecordHistory,
      id: "history",
      current_scope: %{scope: scope},
      auditable_types: [mutation.auditable_type],
      auditable_id: mutation.auditable_id,
      record: nil
    )
  end

  defp text(html, selector) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(selector)
    |> LazyHTML.text()
    |> String.trim()
  end
end
