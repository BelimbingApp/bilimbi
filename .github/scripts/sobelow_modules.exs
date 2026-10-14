workspace_root = File.cwd!()

module_roots =
  workspace_root
  |> Bilimbi.Base.ModuleRegistry.MixDiscovery.discover_workspace!()
  |> Enum.map(& &1.path)

roots = [Path.join(workspace_root, "apps/web") | module_roots]

failed? =
  Enum.reduce(roots, false, fn root, failed? ->
    relative_root = Path.relative_to(root, workspace_root)
    IO.puts("== sobelow #{relative_root}")

    Mix.Task.reenable("sobelow")
    Mix.Task.run("sobelow", ["--root", relative_root, "--private"])

    findings = Sobelow.FindingLog.log()
    failed? = failed? or findings.high != [] or findings.medium != []

    Enum.each([Sobelow.FindingLog, Sobelow.MetaLog, Sobelow.Fingerprint], fn server ->
      if Process.whereis(server), do: GenServer.stop(server)
    end)

    failed?
  end)

if failed?, do: System.halt(1)
