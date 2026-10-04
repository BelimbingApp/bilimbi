defmodule Bilimbi.Core.Address.LocationSuggestion do
  @moduledoc """
  Postcode, division, and locality suggestions for an address form.

  The create page, the address detail editor, and the company panel's
  create-and-attach modal all ask this module. A private cascade in a
  LiveView is the copy it replaced; the detail page used to search with
  different thresholds than the create page.

  `suggest/3` compares the posted params with the previous ones. A country
  change clears the division, postcode, and locality, then resolves a
  postcode that arrived in that same change against the new country. A
  postcode change fills the division and locality when the reference data
  has one match, and clears a value that was itself suggested once the
  operator edits it.
  """

  alias Bilimbi.Core.Geonames

  @type params :: %{optional(String.t()) => String.t()}
  @type auto :: %{admin1_code: boolean(), locality: boolean()}
  @type options :: %{
          admin1: [{String.t(), String.t()}],
          postcodes: [String.t()],
          localities: [String.t()]
        }

  @doc """
  The next form params and which of division and locality were filled from
  the postcode.
  """
  @spec suggest(map(), map() | nil, map() | nil) :: {params(), auto()}
  def suggest(incoming, previous, previous_auto) when is_map(incoming) do
    previous = previous || %{}
    previous_auto = normalize_auto(previous_auto)
    params = normalize_country(incoming)
    country_changed? = field(params, "country_iso") != field(previous, "country_iso")
    postcode_changed? = field(params, "postcode") != field(previous, "postcode")

    cond do
      country_changed? and postcode_changed? and field(params, "postcode") != "" ->
        params
        |> clear_dependents()
        |> Map.put("postcode", field(params, "postcode"))
        |> apply_postcode(%{admin1_code: false, locality: false})

      country_changed? ->
        {clear_dependents(params), %{admin1_code: false, locality: false}}

      postcode_changed? ->
        apply_postcode(params, previous_auto)

      true ->
        {params,
         %{
           admin1_code:
             previous_auto.admin1_code and
               field(params, "admin1_code") == field(previous, "admin1_code"),
           locality:
             previous_auto.locality and field(params, "locality") == field(previous, "locality")
         }}
    end
  end

  @doc """
  Division options, postcode suggestions, and locality suggestions for the
  current params.
  """
  @spec options(map()) :: options()
  def options(params) when is_map(params) do
    country_iso = field(params, "country_iso")
    postcode = field(params, "postcode")
    locality = field(params, "locality")
    admin1_code = field(params, "admin1_code")

    exact_localities =
      country_iso
      |> Geonames.lookup_postcode(postcode)
      |> Enum.map(& &1.place_name)
      |> Enum.reject(&blank?/1)
      |> Enum.uniq()

    localities =
      exact_localities ++
        Geonames.search_city_names(country_iso, locality, admin1_code: admin1_code)

    %{
      admin1: Geonames.admin1_options(country_iso),
      postcodes: Geonames.search_postcodes(country_iso, postcode),
      localities: Enum.uniq(localities)
    }
  end

  defp apply_postcode(params, old_auto) do
    params =
      params
      |> maybe_clear_auto("admin1_code", old_auto.admin1_code)
      |> maybe_clear_auto("locality", old_auto.locality)

    matches = Geonames.lookup_postcode(field(params, "country_iso"), field(params, "postcode"))
    localities = matches |> Enum.map(& &1.place_name) |> Enum.reject(&blank?/1) |> Enum.uniq()
    admin1_code = matching_admin1_code(field(params, "country_iso"), matches)

    params = if admin1_code, do: Map.put(params, "admin1_code", admin1_code), else: params

    params =
      if length(localities) == 1, do: Map.put(params, "locality", hd(localities)), else: params

    {params, %{admin1_code: not is_nil(admin1_code), locality: length(localities) == 1}}
  end

  defp matching_admin1_code(_country_iso, []), do: nil

  defp matching_admin1_code(country_iso, [first | _rest]) do
    raw_code = first.admin1_code

    country_iso
    |> Geonames.list_admin1()
    |> Enum.find_value(fn admin1 ->
      if admin1.code == raw_code or String.ends_with?(admin1.code, ".#{raw_code}"),
        do: admin1.code
    end)
  end

  defp normalize_auto(%{admin1_code: admin1, locality: locality})
       when is_boolean(admin1) and is_boolean(locality) do
    %{admin1_code: admin1, locality: locality}
  end

  defp normalize_auto(_auto), do: %{admin1_code: false, locality: false}

  defp normalize_country(params) do
    Map.update(params, "country_iso", "", fn value ->
      value |> to_string() |> String.trim() |> String.upcase()
    end)
  end

  defp clear_dependents(params) do
    Enum.reduce(~w(admin1_code postcode locality), params, &Map.put(&2, &1, ""))
  end

  defp maybe_clear_auto(params, field_name, true), do: Map.put(params, field_name, "")
  defp maybe_clear_auto(params, _field_name, false), do: params

  defp field(params, name), do: Map.get(params, name, "") || ""

  defp blank?(value), do: is_nil(value) or (is_binary(value) and String.trim(value) == "")
end
