defmodule Bilimbi.Base.Authz.Contributions do
  @moduledoc false

  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider

  @verbs [
    "view",
    "list",
    "create",
    "update",
    "delete",
    "submit",
    "approve",
    "reject",
    "execute",
    "impersonate",
    "manage",
    "grant",
    "revoke",
    "send",
    "react",
    "edit",
    "media",
    "poll",
    "search",
    "assign",
    "review",
    "triage",
    "respond",
    "verify",
    "close",
    "issue",
    "accept",
    "rework",
    "cancel",
    "unlock",
    "upload",
    "follow-up",
    "hod-approve"
  ]

  @capabilities [
    "admin.user.impersonate",
    "admin.authz.role.list",
    "admin.authz.role.view",
    "admin.authz.role.create",
    "admin.authz.role.update",
    "admin.authz.role.delete",
    "admin.authz.principal-role.list",
    "admin.authz.capability.list",
    "admin.authz.principal-capability.list",
    "admin.authz.decision-log.list"
  ]

  @impl true
  def contributions do
    %{
      settings: %{
        definitions: %{
          "authz.decision_log_retention_days" => %{
            type: :integer,
            scopes: [:global],
            default: 90,
            label: "Authorization log retention",
            help: "Days to retain authorization decision logs.",
            editable: "operator",
            capability: "admin.authz.decision-log.list"
          }
        },
        runtime_claims: []
      },
      authz: %{
        domains: %{"admin" => "Administrative operations"},
        verbs: @verbs,
        capabilities: @capabilities,
        roles: %{
          "core_admin" => %{
            name: "Core Administrator",
            description:
              "System role with all capabilities. New capabilities are automatically granted.",
            grant_all: true
          },
          "tenant_owner" => %{
            name: "Tenant Owner",
            description:
              "Full control within a single tenant: commerce, AI, messaging, company, employees, and addresses. No platform administration."
          },
          "auditor" => %{
            name: "Auditor",
            description:
              "Read-only access to decision logs, system logs, and sessions for compliance.",
            capabilities: ["admin.authz.decision-log.list"]
          },
          "system_viewer" => %{
            name: "System Viewer",
            description:
              "Read-only access to system infrastructure: tables, jobs, cache, schedule, and sessions."
          }
        }
      }
    }
  end
end
