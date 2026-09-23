defmodule BilimbiWeb.ConnectionBannersCssTest do
  @moduledoc """
  A page reports a dropped connection once. `connection_banners/1` marks every
  pair it renders and the layout's pair `yields`; `app.css` is what makes a
  yielding pair stand down while any other pair is in the document. The rule
  has to key on the component's markers, not on the ids of the layout's pair
  or on the modal case, or the Design Library's specimen could not stand in
  for the layout's outlet the way a dialog's does.
  """

  use ExUnit.Case, async: true

  @css_path Path.expand("../assets/css/app.css", __DIR__)

  test "a yielding pair is hidden whenever another pair is in the document" do
    css = File.read!(@css_path)

    assert css =~
             ~r/^body:has\(\[data-connection-banners\]:not\(\[data-yields\]\)\) \[data-connection-banners\]\[data-yields\] \{\n\s*visibility: hidden;\n\}/m,
           "app.css has no rule that hides a yielding connection pair while another pair is present"
  end

  test "no rule names the layout's banners or the modal case for that" do
    css = File.read!(@css_path)

    refute css =~ "#connection-client-error"
    refute css =~ "#connection-server-error"
    refute css =~ ~r/dialog:modal\)[^\n]*data-connection-banners/
  end
end
