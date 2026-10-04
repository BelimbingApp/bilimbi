defmodule BilimbiWeb.ErrorHTML do
  @moduledoc """
  HTML responses for endpoint errors.

  `layout: false` in the endpoint config, so each template is the whole
  document. The body is the credential card (`Bilimbi.Base.UI.Layouts.auth/1`):
  brand bar, one sentence, and a way back to the sign-in page.
  """

  use Bilimbi.Base.UI, :html

  embed_templates "error_html/*"

  # Statuses without their own template keep the plain status word.
  def render(template, _assigns) when is_binary(template) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
