defmodule BilimbiWeb.MountedTailwindSourceTest do
  use ExUnit.Case, async: true

  @workspace_root Path.expand("../../../..", __DIR__)

  test "Tailwind emits classes used only by mounted Domain and Extension templates" do
    root =
      Path.join(
        System.tmp_dir!(),
        "bilimbi-tailwind-mount-#{System.unique_integer([:positive, :monotonic])}"
      )

    on_exit(fn -> File.rm_rf!(root) end)

    source = File.read!(Path.join(@workspace_root, "apps/web/assets/css/app.css"))

    mount_sources =
      source
      |> String.split("\n")
      |> Enum.filter(
        &Regex.match?(~r/^@source "\.\.\/\.\.\/\.\.\/\.\.\/apps\/(domains|extensions)";$/, &1)
      )

    assert length(mount_sources) == 2

    css = Path.join(root, "apps/web/assets/css/app.css")
    File.mkdir_p!(Path.dirname(css))
    File.write!(css, "@import \"tailwindcss\" source(none);\n" <> Enum.join(mount_sources, "\n"))

    for {layer, color} <- [{"domains", "#123456"}, {"extensions", "#654321"}] do
      repo = Path.join([root, "apps", layer, "fixture"])
      File.mkdir_p!(repo)
      {_, 0} = System.cmd("git", ["init", "-q", repo])
      template = Path.join(repo, "widget/lib/widget/web/index_live.html.heex")
      File.mkdir_p!(Path.dirname(template))
      File.write!(template, "<div class=\"text-[#{color}]\">Mounted</div>\n")
    end

    output = Path.join(root, "output.css")
    unless File.exists?(Tailwind.bin_path()), do: Tailwind.install()

    {_result, 0} =
      System.cmd(Tailwind.bin_path(), ["--input=#{css}", "--output=#{output}"],
        cd: root,
        stderr_to_stdout: true
      )

    built = File.read!(output)
    assert built =~ "#123456"
    assert built =~ "#654321"
  end
end
