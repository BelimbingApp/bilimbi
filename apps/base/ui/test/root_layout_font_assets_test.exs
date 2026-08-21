defmodule Bilimbi.Base.UI.RootLayoutFontAssetsTest do
  use ExUnit.Case, async: true

  @workspace_root Path.expand("../../../..", __DIR__)
  @root_layout Path.join(@workspace_root, "apps/base/ui/lib/ui/layouts/root.html.heex")
  @app_css Path.join(@workspace_root, "apps/web/assets/css/app.css")
  @font_paths [
    Path.join(@workspace_root, "apps/web/priv/static/fonts/instrument-sans-variable.woff2"),
    Path.join(@workspace_root, "apps/web/priv/static/fonts/instrument-sans-variable-italic.woff2")
  ]

  test "the root layout uses locally vendored Instrument Sans" do
    root_layout = File.read!(@root_layout)
    app_css = File.read!(@app_css)

    refute root_layout =~ "fonts.googleapis.com"
    refute root_layout =~ "fonts.gstatic.com"

    assert app_css =~ "font-family: \"Instrument Sans\""
    assert app_css =~ "font-weight: 400 700"
    assert app_css =~ "font-style: italic"
    assert app_css =~ "font-display: swap"
    assert app_css =~ "url(\"/fonts/instrument-sans-variable.woff2\")"
    assert app_css =~ "url(\"/fonts/instrument-sans-variable-italic.woff2\")"
  end

  test "both Instrument Sans variants are committed as WOFF2 assets" do
    Enum.each(@font_paths, fn path ->
      assert <<"wOF2", _rest::binary>> = File.read!(path)
    end)
  end
end
