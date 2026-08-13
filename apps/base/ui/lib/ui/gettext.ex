defmodule Bilimbi.Base.UI.Gettext do
  @moduledoc """
  Gettext backend for shared UI components and layouts.
  """
  use Gettext.Backend, otp_app: :bilimbi_base_ui
end
