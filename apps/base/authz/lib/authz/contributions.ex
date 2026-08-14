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
      # Belimbing's app/Base/Authz/Config/menu.php, ported whole rather than
      # one item per slice. Items whose routes are not served yet are pruned
      # by Base.UI.Nav, so each appears by itself as its screen lands and the
      # declared shape stays the reference rather than a running total.
      menu: [
        %{
          id: "admin.authz",
          label: "Authorization",
          icon: "shield-check",
          parent: "admin",
          order: 20
        },
        %{
          id: "admin.authz.capability",
          label: "Capabilities",
          icon: "puzzle-piece",
          parent: "admin.authz",
          route: "/authz/capabilities",
          capability: "admin.authz.capability.list",
          order: 10
        },
        %{
          id: "admin.authz.role",
          label: "Roles",
          icon: "shield-check",
          parent: "admin.authz",
          route: "/authz/roles",
          capability: "admin.authz.role.list",
          order: 20
        },
        %{
          id: "admin.authz.principal-role",
          label: "Principal Roles",
          icon: "user-circle",
          parent: "admin.authz",
          route: "/authz/principal-roles",
          capability: "admin.authz.principal-role.list",
          order: 30
        },
        %{
          id: "admin.authz.principal-capability",
          label: "Principal Capabilities",
          icon: "key",
          parent: "admin.authz",
          route: "/authz/principal-capabilities",
          capability: "admin.authz.principal-capability.list",
          order: 40
        },
        %{
          id: "admin.authz.decision-log",
          label: "Decision Logs",
          icon: "clipboard-document-list",
          parent: "admin.authz",
          route: "/authz/decision-logs",
          capability: "admin.authz.decision-log.list",
          order: 50
        }
      ],
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
