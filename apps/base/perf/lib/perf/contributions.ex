defmodule Bilimbi.Base.Perf.Contributions do
  @moduledoc false

  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider

  @view "admin.system.perf.view"
  @manage "admin.system.perf.manage"

  @impl true
  def contributions do
    %{
      settings: %{
        definitions: definitions(),
        runtime_claims: []
      },
      authz: %{
        capabilities: [@view, @manage],
        roles: %{"system_viewer" => %{capabilities: [@view]}}
      },
      menu: [
        %{
          id: "admin.system.performance",
          label: "Performance",
          icon: "chart-bar",
          parent: "admin.system.diagnostics",
          route: "/system/performance",
          capability: @view,
          order: 20
        }
      ],
      dashboard: [
        %{
          id: "base-perf-health",
          label: "Performance health",
          size: :small,
          order: 50,
          capability: @view
        }
      ],
      schedule: %{
        definitions: [
          %{
            key: "base/perf.retention",
            name: "Prune performance history",
            expression: "17 3 * * *",
            timezone: "Etc/UTC",
            task_name: "Base Perf retention",
            worker: Bilimbi.Base.Perf.RetentionWorker,
            args: %{},
            overlap: :forbid,
            misfire: :coalesce
          }
        ]
      }
    }
  end

  defp definitions do
    %{
      "perf.enabled" =>
        setting(:boolean, true, "Performance history", "Record redacted performance history."),
      "perf.minimum_duration_ms" =>
        setting(:integer, 100, "Minimum duration", "Ignore faster observations.", 0, 60_000),
      "perf.sample_rate" =>
        setting(
          :float,
          1.0,
          "Sample rate",
          "Fraction of eligible observations to retain.",
          0.0,
          1.0
        ),
      "perf.slow_threshold_ms" =>
        setting(
          :integer,
          1_000,
          "Slow threshold",
          "Threshold used by regression diagnostics.",
          1,
          3_600_000
        ),
      "perf.history.keep_days" =>
        setting(:integer, 30, "History retention", "Maximum history age in days.", 1, 3650),
      "perf.history.max_rows" =>
        setting(
          :integer,
          200_000,
          "History row limit",
          "Maximum retained observations.",
          1_000,
          1_000_000
        )
    }
  end

  defp setting(type, default, label, help, minimum \\ nil, maximum \\ nil) do
    %{
      type: type,
      scopes: [:global],
      default: default,
      label: label,
      help: help,
      editable: "operator",
      capability: @manage
    }
    |> maybe_bound(:minimum, minimum)
    |> maybe_bound(:maximum, maximum)
  end

  defp maybe_bound(setting, _key, nil), do: setting
  defp maybe_bound(setting, key, value), do: Map.put(setting, key, value)
end
