defmodule Bilimbi.Base.UI.Gettext do
  @moduledoc """
  The one Gettext backend for shared UI and the host.
  """
  use Gettext.Backend, otp_app: :bilimbi_base_ui
end
