defmodule Bilimbi.Base.Locale do
  @moduledoc """
  Supported regional locales and explicit-scope locale resolution.

  `ui.locale` belongs to Base Locale but is stored through Base Settings. The
  only legal setting scopes here are global (`nil`) and a user
  `Bilimbi.Base.Settings.Scope`; company and tenant scopes are deliberately not
  accepted. Callers resolve identity and authorization at the edge and pass the
  resulting scope rather than asking this Base module to find a Core user.

  Resolution is stateless and follows one order:

    1. an explicit user override;
    2. a valid explicitly stored global locale and its provenance;
    3. a supported locale inferred from bounded bootstrap facts and persisted
       globally once;
    4. the declared `en-MY` default.

  The regional code remains intact for number, currency, and later date/time
  consumers. `language/1` separately returns the language code a Gettext
  adapter applies. No process-global locale is changed here, so concurrent and
  long-lived processes cannot inherit another caller's resolved state.
  """

  alias Bilimbi.Base.Locale.Bootstrap
  alias Bilimbi.Base.Locale.Resolved
  alias Bilimbi.Base.Settings
  alias Bilimbi.Base.Settings.Scope

  @locale_key "ui.locale"
  @source_key "ui.locale_source"
  @inferred_country_key "ui.locale_inferred_country"

  @manual "manual"
  @platform_operator_address "platform_operator_address"
  @declared_default "declared_default"
  @sources [@manual, @platform_operator_address, @declared_default]

  @fallback_locale "en-MY"

  @supported_locales %{
    "ar-SA" => %{label: "Arabic (Saudi Arabia)", language: "ar"},
    "de-CH" => %{label: "German (Switzerland)", language: "de"},
    "de-DE" => %{label: "German (Germany)", language: "de"},
    "en-AU" => %{label: "English (Australia)", language: "en"},
    "en-CA" => %{label: "English (Canada)", language: "en"},
    "en-GB" => %{label: "English (United Kingdom)", language: "en"},
    "en-MY" => %{label: "English (Malaysia)", language: "en"},
    "en-SG" => %{label: "English (Singapore)", language: "en"},
    "en-US" => %{label: "English (United States)", language: "en"},
    "es-ES" => %{label: "Spanish (Spain)", language: "es"},
    "fr-CA" => %{label: "French (Canada)", language: "fr"},
    "fr-FR" => %{label: "French (France)", language: "fr"},
    "hi-IN" => %{label: "Hindi (India)", language: "hi"},
    "id-ID" => %{label: "Indonesian (Indonesia)", language: "id"},
    "it-IT" => %{label: "Italian (Italy)", language: "it"},
    "ja-JP" => %{label: "Japanese (Japan)", language: "ja"},
    "ko-KR" => %{label: "Korean (South Korea)", language: "ko"},
    "ms-MY" => %{label: "Malay (Malaysia)", language: "ms"},
    "nl-NL" => %{label: "Dutch (Netherlands)", language: "nl"},
    "pl-PL" => %{label: "Polish (Poland)", language: "pl"},
    "pt-BR" => %{label: "Portuguese (Brazil)", language: "pt"},
    "ru-RU" => %{label: "Russian (Russia)", language: "ru"},
    "th-TH" => %{label: "Thai (Thailand)", language: "th"},
    "tr-TR" => %{label: "Turkish (Turkey)", language: "tr"},
    "vi-VN" => %{label: "Vietnamese (Vietnam)", language: "vi"},
    "zh-CN" => %{label: "Chinese (China)", language: "zh"},
    "zh-HK" => %{label: "Chinese (Hong Kong)", language: "zh"},
    "zh-TW" => %{label: "Chinese (Taiwan)", language: "zh"}
  }

  @language_defaults %{
    "ar" => "ar-SA",
    "de" => "de-DE",
    "en" => "en-MY",
    "es" => "es-ES",
    "fr" => "fr-FR",
    "hi" => "hi-IN",
    "id" => "id-ID",
    "it" => "it-IT",
    "ja" => "ja-JP",
    "ko" => "ko-KR",
    "ms" => "ms-MY",
    "nl" => "nl-NL",
    "pl" => "pl-PL",
    "pt" => "pt-BR",
    "ru" => "ru-RU",
    "th" => "th-TH",
    "tr" => "tr-TR",
    "vi" => "vi-VN",
    "zh" => "zh-CN"
  }

  @country_overrides %{
    "AU" => "en-AU",
    "BR" => "pt-BR",
    "CA" => "en-CA",
    "CH" => "de-CH",
    "CN" => "zh-CN",
    "DE" => "de-DE",
    "ES" => "es-ES",
    "FR" => "fr-FR",
    "GB" => "en-GB",
    "HK" => "zh-HK",
    "ID" => "id-ID",
    "IN" => "hi-IN",
    "IT" => "it-IT",
    "JP" => "ja-JP",
    "KR" => "ko-KR",
    "MY" => "en-MY",
    "NL" => "nl-NL",
    "PL" => "pl-PL",
    "RU" => "ru-RU",
    "SA" => "ar-SA",
    "SG" => "en-SG",
    "TH" => "th-TH",
    "TR" => "tr-TR",
    "TW" => "zh-TW",
    "US" => "en-US",
    "VN" => "vi-VN"
  }

  @type locale_scope :: %Scope{type: :user} | nil

  @doc "The canonical installation fallback and declared Settings default."
  @spec fallback_locale() :: String.t()
  def fallback_locale, do: @fallback_locale

  @doc "The immutable supported regional catalogue keyed by canonical code."
  @spec supported_locales() :: %{
          required(String.t()) => %{label: String.t(), language: String.t()}
        }
  def supported_locales, do: @supported_locales

  @doc "Whether `locale` is already an exact supported regional code."
  @spec supports?(term()) :: boolean()
  def supports?(locale) when is_binary(locale), do: Map.has_key?(@supported_locales, locale)
  def supports?(_locale), do: false

  @doc "The catalogue label, or the input itself when its regional code is unknown."
  @spec label(String.t()) :: String.t()
  def label(locale) when is_binary(locale) do
    get_in(@supported_locales, [locale, :label]) || locale
  end

  @doc "The translation language carried by a regional locale code."
  @spec language(String.t()) :: String.t()
  def language(locale) when is_binary(locale) do
    get_in(@supported_locales, [locale, :language]) ||
      locale |> String.split("-", parts: 2) |> List.first() |> String.downcase()
  end

  @doc """
  Normalizes a supported locale or language to its canonical regional code.

  Case and `_`/`-` separator differences are normalized. A language-only input
  uses the catalogue's declared regional default. Unsupported, blank, and
  non-string values return `nil`.
  """
  @spec normalize(term()) :: String.t() | nil
  def normalize(locale) when is_binary(locale) do
    locale
    |> String.trim()
    |> String.replace("_", "-")
    |> String.split("-")
    |> normalize_parts()
  end

  def normalize(_locale), do: nil

  @doc "Infers a supported locale from bounded platform-operator address facts."
  @spec infer(Bootstrap.t()) :: String.t() | nil
  def infer(%Bootstrap{country_iso: country_iso, languages: languages})
      when is_binary(country_iso) do
    country_iso = country_iso |> String.trim() |> String.upcase()

    case Map.get(@country_overrides, country_iso) do
      locale when is_binary(locale) -> locale
      nil -> infer_from_languages(languages, country_iso)
    end
  end

  def infer(%Bootstrap{}), do: nil

  @doc "Reads the normalized locale for an explicit global or user Settings scope."
  @spec locale(locale_scope()) :: String.t()
  def locale(nil), do: normalize_setting(Settings.get(@locale_key, nil))

  def locale(%Scope{type: :user} = scope),
    do: normalize_setting(Settings.get(@locale_key, scope))

  @doc "Whether the explicit global or user scope has its own locale row."
  @spec overridden?(locale_scope()) :: boolean()
  def overridden?(nil), do: Settings.overridden?(@locale_key, nil)

  def overridden?(%Scope{type: :user} = scope),
    do: Settings.overridden?(@locale_key, scope)

  @doc """
  Stores a normalized manual locale at an explicit global or user scope.

  A global manual choice also records manual provenance and removes stale
  inferred-country state. Unsupported values normalize to the declared
  fallback, matching inherited stored-value reads.
  """
  @spec put(locale_scope(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def put(nil, locale) when is_binary(locale) do
    locale = normalize_setting(locale)

    with {:ok, ^locale} <- Settings.put(@locale_key, locale, nil),
         {:ok, @manual} <- Settings.put(@source_key, @manual, nil),
         :ok <- Settings.delete(@inferred_country_key, nil) do
      {:ok, locale}
    end
  end

  def put(%Scope{type: :user} = scope, locale) when is_binary(locale) do
    locale = normalize_setting(locale)
    Settings.put(@locale_key, locale, scope)
  end

  @doc "Removes the explicit global or user locale so the next source can resolve."
  @spec delete(locale_scope()) :: :ok
  def delete(nil) do
    :ok = Settings.delete(@locale_key, nil)
    :ok = Settings.delete(@source_key, nil)
    Settings.delete(@inferred_country_key, nil)
  end

  def delete(%Scope{type: :user} = scope), do: Settings.delete(@locale_key, scope)

  @doc """
  Resolves one scope without changing process-global locale state.

  `bootstrap` is `nil` before Core can supply a platform-operator address. A
  successful inference is persisted globally with exact provenance and is not
  rerun while that supported global row remains present. Before the canonical
  Settings table exists, resolution returns the declared default; every other
  database error remains visible.
  """
  @spec resolve(locale_scope(), Bootstrap.t() | nil) :: Resolved.t()
  def resolve(scope, bootstrap \\ nil) do
    do_resolve(scope, bootstrap)
  rescue
    error in Postgrex.Error ->
      if match?(%{postgres: %{code: :undefined_table}}, error) do
        resolved(@fallback_locale, @declared_default)
      else
        reraise error, __STACKTRACE__
      end
  end

  defp do_resolve(%Scope{type: :user} = scope, bootstrap) do
    if overridden?(scope) do
      resolved(locale(scope), @manual)
    else
      resolve_global(bootstrap)
    end
  end

  defp do_resolve(nil, bootstrap), do: resolve_global(bootstrap)

  defp resolve_global(bootstrap) do
    stored_locale = if overridden?(nil), do: Settings.get(@locale_key, nil)

    case normalize(stored_locale) do
      locale when is_binary(locale) ->
        resolved(locale, stored_source(), stored_country())

      nil ->
        resolve_bootstrap(bootstrap)
    end
  end

  defp resolve_bootstrap(%Bootstrap{} = bootstrap) do
    with country when is_binary(country) <- normalize_country(bootstrap.country_iso),
         locale when is_binary(locale) <- infer(bootstrap) do
      persist_inferred!(locale, country)
      resolved(locale, @platform_operator_address, country)
    else
      nil ->
        resolved(locale(nil), @declared_default)
    end
  end

  defp resolve_bootstrap(nil), do: resolved(locale(nil), @declared_default)

  defp persist_inferred!(locale, country) do
    put_setting!(@locale_key, locale)
    put_setting!(@source_key, @platform_operator_address)
    put_setting!(@inferred_country_key, country)
  end

  defp put_setting!(key, value) do
    case Settings.put(key, value, nil) do
      {:ok, ^value} -> :ok
      {:error, changeset} -> raise "could not persist #{key}: #{inspect(changeset.errors)}"
    end
  end

  defp stored_source do
    case Settings.get(@source_key, nil) do
      source when source in @sources -> source
      _source -> @manual
    end
  end

  defp stored_country do
    case Settings.get(@inferred_country_key, nil) do
      country when is_binary(country) -> normalize_country(country)
      _country -> nil
    end
  end

  defp resolved(locale, source, country \\ nil) do
    %Resolved{
      locale: locale,
      language: language(locale),
      source: source,
      inferred_country: country
    }
  end

  defp normalize_setting(locale), do: normalize(locale) || @fallback_locale

  defp normalize_parts([language]) when language != "" do
    Map.get(@language_defaults, String.downcase(language))
  end

  defp normalize_parts([language, region | _rest]) when language != "" and region != "" do
    normalized = String.downcase(language) <> "-" <> String.upcase(region)
    if supports?(normalized), do: normalized
  end

  defp normalize_parts(_parts), do: nil

  defp infer_from_languages(languages, country_iso) when is_binary(languages) do
    languages
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.flat_map(&language_candidates(&1, country_iso))
    |> Enum.uniq()
    |> Enum.find_value(&normalize/1)
  end

  defp infer_from_languages(_languages, _country_iso), do: nil

  defp language_candidates(language, country_iso) do
    parts = language |> String.replace("_", "-") |> String.split("-")
    base_language = parts |> List.first() |> to_string() |> String.downcase()

    if base_language == "" do
      []
    else
      explicit_region =
        case parts do
          [_language, region | _rest] when region != "" ->
            [base_language <> "-" <> String.upcase(region)]

          _parts ->
            []
        end

      explicit_region ++ [base_language <> "-" <> country_iso, base_language]
    end
  end

  defp normalize_country(country) when is_binary(country) do
    case country |> String.trim() |> String.upcase() do
      "" -> nil
      country -> country
    end
  end
end
