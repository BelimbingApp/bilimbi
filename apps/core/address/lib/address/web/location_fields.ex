defmodule Bilimbi.Core.Address.Web.LocationFields do
  @moduledoc """
  The country, division, postcode, and locality fields of an address form.

  Create, the detail editor, and the company panel's create modal render
  this component. A hand-written copy of the fieldset is the markup it
  replaced. Callers keep their DOM ids and the nouns on the labels; the
  suggestion rules live in `Bilimbi.Core.Address.LocationSuggestion`.
  """

  use Bilimbi.Base.UI, :html

  attr(:form, :any, required: true)
  attr(:ids, :map, required: true, doc: "DOM ids for the four fields, two lists, and two notes")
  attr(:country_options, :list, required: true)
  attr(:admin1_options, :list, required: true)
  attr(:postcode_options, :list, required: true)
  attr(:locality_options, :list, required: true)
  attr(:auto, :map, required: true, doc: "`%{admin1_code: boolean, locality: boolean}`")
  attr(:country_blank?, :boolean, required: true)

  attr(:admin1_label, :string, default: "State or province")
  attr(:admin1_prompt, :string, default: "Choose a division")
  attr(:postcode_label, :string, default: "Postcode")
  attr(:locality_label, :string, default: "Locality")

  def location_fields(assigns) do
    ~H"""
    <div class="grid gap-x-4 sm:grid-cols-2">
      <.combobox
        field={@form[:country_iso]}
        id={@ids.country}
        label="Country"
        placeholder="Choose a country"
        options={@country_options}
      />
      <div>
        <.input
          field={@form[:admin1_code]}
          id={@ids.admin1}
          type="select"
          label={@admin1_label}
          prompt={@admin1_prompt}
          options={@admin1_options}
          disabled={@admin1_options == []}
        />
        <p :if={@auto.admin1_code} id={@ids.admin1_auto} class="-mt-2 mb-4 text-xs text-ink-subtle">
          Suggested from postcode
        </p>
      </div>
      <div>
        <.input
          field={@form[:postcode]}
          id={@ids.postcode}
          label={@postcode_label}
          list={@ids.postcode_list}
          maxlength="255"
          disabled={@country_blank?}
        />
        <datalist id={@ids.postcode_list}>
          <option :for={postcode <- @postcode_options} value={postcode}></option>
        </datalist>
      </div>
      <div>
        <.input
          field={@form[:locality]}
          id={@ids.locality}
          label={@locality_label}
          list={@ids.locality_list}
          maxlength="255"
          disabled={@country_blank?}
        />
        <datalist id={@ids.locality_list}>
          <option :for={locality <- @locality_options} value={locality}></option>
        </datalist>
        <p :if={@auto.locality} id={@ids.locality_auto} class="-mt-2 mb-4 text-xs text-ink-subtle">
          Suggested from postcode
        </p>
      </div>
    </div>
    """
  end
end
