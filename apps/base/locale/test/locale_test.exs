defmodule Bilimbi.Base.LocaleTest do
  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Locale
  alias Bilimbi.Base.Locale.Bootstrap
  alias Bilimbi.Base.Locale.Contributions
  alias Bilimbi.Base.Locale.Resolved
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Settings
  alias Bilimbi.Base.Settings.ContributionValidator
  alias Bilimbi.Base.Settings.Definition
  alias Bilimbi.Base.Settings.Scope
  alias Bilimbi.Base.Settings.TestFixtures

  setup_all do
    settings =
      ContributionValidator.validate_contributions!([
        %{
          descriptor: %{id: "base/locale"},
          payload: Contributions.contributions().settings
        }
      ])

    ContributionRegistry.put_snapshot_for_test!(%{
      graph_fingerprint: "base-locale-test",
      consumers: %{settings: settings}
    })

    on_exit(&ContributionRegistry.clear_for_test!/0)
    :ok
  end

  setup tags do
    unless tags[:without_settings_table], do: TestFixtures.create_settings_table!()
    :ok
  end

  test "declares the exact regional catalogue and fallback" do
    assert Locale.fallback_locale() == "en-MY"

    assert Locale.supported_locales() |> Map.keys() |> Enum.sort() == [
             "ar-SA",
             "de-CH",
             "de-DE",
             "en-AU",
             "en-CA",
             "en-GB",
             "en-MY",
             "en-SG",
             "en-US",
             "es-ES",
             "fr-CA",
             "fr-FR",
             "hi-IN",
             "id-ID",
             "it-IT",
             "ja-JP",
             "ko-KR",
             "ms-MY",
             "nl-NL",
             "pl-PL",
             "pt-BR",
             "ru-RU",
             "th-TH",
             "tr-TR",
             "vi-VN",
             "zh-CN",
             "zh-HK",
             "zh-TW"
           ]

    assert Locale.label("de-CH") == "German (Switzerland)"
    assert Locale.language("de-CH") == "de"
    assert Locale.label("xx-ZZ") == "xx-ZZ"
  end

  test "normalizes case, separators, and declared language defaults only" do
    assert Locale.normalize("  EN_my  ") == "en-MY"
    assert Locale.normalize("de-ch") == "de-CH"
    assert Locale.normalize("fr") == "fr-FR"
    assert Locale.normalize("zh") == "zh-CN"

    assert Locale.normalize("en-ZZ") == nil
    assert Locale.normalize("xx") == nil
    assert Locale.normalize("") == nil
    assert Locale.normalize("   ") == nil
    assert Locale.normalize(nil) == nil
  end

  test "country overrides precede ordered language candidates" do
    assert Locale.infer(%Bootstrap{country_iso: "my", languages: "ms"}) == "en-MY"
    assert Locale.infer(%Bootstrap{country_iso: "US", languages: "de-CH"}) == "en-US"

    assert Locale.infer(%Bootstrap{country_iso: "ZZ", languages: "xx, de-CH, fr"}) ==
             "de-CH"

    assert Locale.infer(%Bootstrap{country_iso: "ZZ", languages: "de-AT"}) == "de-DE"
    assert Locale.infer(%Bootstrap{country_iso: "ZZ", languages: nil}) == nil
  end

  test "contributes ui.locale at user and global scope plus exact provenance claims" do
    assert %Definition{
             owner: "base/locale",
             type: :string,
             scopes: [:user, :global],
             default: "en-MY",
             nullable: false,
             encrypted: false
           } = Settings.definition!("ui.locale")

    assert Settings.runtime_claims() == ["ui.locale_inferred_country", "ui.locale_source"]
  end

  test "user overrides are isolated and otherwise inherit the global locale" do
    first = Scope.user(101)
    second = Scope.user(202)

    assert {:ok, "de-DE"} = Locale.put(nil, "de_de")
    assert Locale.locale(first) == "de-DE"
    assert Locale.locale(second) == "de-DE"

    assert {:ok, "fr-CA"} = Locale.put(first, "FR_ca")
    assert Locale.locale(first) == "fr-CA"
    assert Locale.locale(second) == "de-DE"

    assert :ok = Locale.delete(first)
    assert Locale.locale(first) == "de-DE"
  end

  test "global manual writes record source and clear stale inference country" do
    assert {:ok, "MY"} = Settings.put("ui.locale_inferred_country", "MY", nil)
    assert {:ok, "fr-FR"} = Locale.put(nil, "fr")

    assert Settings.get("ui.locale_source", nil) == "manual"
    assert Settings.get("ui.locale_inferred_country", nil) == nil

    assert %Resolved{
             locale: "fr-FR",
             language: "fr",
             source: "manual",
             inferred_country: nil
           } = Locale.resolve(nil)
  end

  test "one-time bootstrap inference persists exact provenance" do
    bootstrap = %Bootstrap{country_iso: "us", languages: "de"}

    assert %Resolved{
             locale: "en-US",
             language: "en",
             source: "platform_operator_address",
             inferred_country: "US"
           } = Locale.resolve(nil, bootstrap)

    assert Settings.get("ui.locale", nil) == "en-US"
    assert Settings.get("ui.locale_source", nil) == "platform_operator_address"
    assert Settings.get("ui.locale_inferred_country", nil) == "US"

    assert %Resolved{locale: "en-US", inferred_country: "US"} =
             Locale.resolve(nil, %Bootstrap{country_iso: "DE", languages: "de"})
  end

  test "invalid stored global locale does not block bootstrap inference" do
    assert {:ok, "unsupported"} = Settings.put("ui.locale", "unsupported", nil)

    assert %Resolved{locale: "de-DE", source: "platform_operator_address"} =
             Locale.resolve(nil, %Bootstrap{country_iso: "DE"})
  end

  test "absence of bootstrap facts resolves the declared default without provenance rows" do
    assert %Resolved{
             locale: "en-MY",
             language: "en",
             source: "declared_default",
             inferred_country: nil
           } = Locale.resolve(nil)

    refute Locale.overridden?(nil)
    assert Settings.get("ui.locale_source", nil) == nil
    assert Settings.get("ui.locale_inferred_country", nil) == nil
  end

  @tag :without_settings_table
  test "pre-provisioning returns the declared default without inventing provenance" do
    assert %Resolved{
             locale: "en-MY",
             language: "en",
             source: "declared_default",
             inferred_country: nil
           } = Locale.resolve(nil, %Bootstrap{country_iso: "DE", languages: "de"})
  end

  test "database failures other than a missing Settings table remain visible" do
    Ecto.Adapters.SQL.query!(Repo, "ALTER TABLE base_settings DROP COLUMN value", [])

    error =
      assert_raise Postgrex.Error, fn ->
        Locale.resolve(nil, %Bootstrap{country_iso: "DE", languages: "de"})
      end

    assert error.postgres.code == :undefined_column
  end

  test "bootstrap facts without a country do not infer or persist a locale" do
    assert %Resolved{locale: "en-MY", source: "declared_default"} =
             Locale.resolve(nil, %Bootstrap{country_iso: "", languages: "de"})

    refute Locale.overridden?(nil)
    assert Settings.get("ui.locale_source", nil) == nil
  end

  test "concurrent callers retain their own explicit scope" do
    first = Scope.user(301)
    second = Scope.user(302)

    assert {:ok, "de-CH"} = Locale.put(first, "de-CH")
    assert {:ok, "zh-TW"} = Locale.put(second, "zh-TW")

    tasks =
      for scope <- [first, second] do
        Task.async(fn -> Locale.resolve(scope) end)
      end

    assert tasks |> Enum.map(&Task.await/1) |> Enum.map(& &1.locale) == ["de-CH", "zh-TW"]
  end

  test "company and tenant scopes cannot forge locale writes" do
    assert_raise FunctionClauseError, fn ->
      apply(Locale, :put, [Scope.company(1), "fr-FR"])
    end

    assert_raise FunctionClauseError, fn ->
      apply(Locale, :put, [Scope.tenant(1), "fr-FR"])
    end

    assert_raise FunctionClauseError, fn ->
      apply(Locale, :resolve, [Scope.company(1)])
    end
  end
end
