defmodule BilimbiWeb.MountedTailwindSourceTest do
  use ExUnit.Case, async: true

  @workspace_root Path.expand("../../../..", __DIR__)

  test "Tailwind emits classes used only by gitignored mounted Domain and Extension templates" do
    assert File.exists?(Tailwind.bin_path()),
           "the Tailwind binary is missing; run `mix assets.setup` in apps/web"

    root =
      Path.join(
        System.tmp_dir!(),
        "bilimbi-tailwind-mount-#{System.unique_integer([:positive, :monotonic])}"
      )

    on_exit(fn -> File.rm_rf!(root) end)

    assets = Path.join(root, "apps/web/assets")
    File.mkdir_p!(Path.join(assets, "css"))
    File.cp_r!(Path.join(@workspace_root, "apps/web/assets/vendor"), Path.join(assets, "vendor"))

    File.cp!(
      Path.join(@workspace_root, "apps/web/assets/css/app.css"),
      Path.join(assets, "css/app.css")
    )

    for file <- [".gitignore", "apps/domains/.ignore", "apps/extensions/.ignore"] do
      File.mkdir_p!(Path.dirname(Path.join(root, file)))
      File.cp!(Path.join(@workspace_root, file), Path.join(root, file))
    end

    File.ln_s!(Path.join(@workspace_root, "deps"), Path.join(root, "deps"))
    {_, 0} = System.cmd("git", ["init", "-q", root])

    for {layer, color} <- [{"domains", "#123456"}, {"extensions", "#654321"}] do
      repo = Path.join([root, "apps", layer, "fixture"])
      File.mkdir_p!(repo)
      {_, 0} = System.cmd("git", ["init", "-q", repo])
      template = Path.join(repo, "widget/lib/widget/web/index_live.html.heex")
      File.mkdir_p!(Path.dirname(template))
      File.write!(template, "<div class=\"text-[#{color}]\">Mounted</div>\n")
    end

    for mounted <- ["apps/domains/fixture", "apps/extensions/fixture"] do
      assert {_, 0} = System.cmd("git", ["check-ignore", "-q", mounted], cd: root)
    end

    output = Path.join(root, "output.css")
    node_path = Enum.join([Path.join(@workspace_root, "deps"), Mix.Project.build_path()], ":")

    {result, status} =
      System.cmd(
        Tailwind.bin_path(),
        ["--input=assets/css/app.css", "--output=#{output}"],
        cd: Path.join(root, "apps/web"),
        env: [{"NODE_PATH", node_path}],
        stderr_to_stdout: true
      )

    assert status == 0, result

    built = File.read!(output)
    assert built =~ "#123456"
    assert built =~ "#654321"
  end
end
