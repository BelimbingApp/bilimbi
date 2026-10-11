defmodule Bilimbi.Base.Settings.ArrayFormTest do
  use Bilimbi.Base.Database.DataCase, async: false
  alias Bilimbi.Base.Settings
  alias Bilimbi.Base.Settings.{ContributionValidator, Form}
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry

  setup do
    Bilimbi.Base.Settings.TestFixtures.create_settings_table!()

    settings =
      ContributionValidator.validate_contributions!([
        %{
          descriptor: %{id: "base/settings"},
          payload: %{
            definitions: %{
              "tests.structured" => %{
                type: :array,
                scopes: [:global],
                default: %{},
                editable: "test",
                label: "Structured value",
                help: "Object or array"
              }
            },
            runtime_claims: []
          }
        }
      ])

    ContributionRegistry.put_consumers_for_test!(%{settings: settings})
    on_exit(&ContributionRegistry.clear_for_test!/0)
  end

  test "text submissions preserve JSON objects and arrays in settings persistence" do
    fields = Form.fields(["test"], nil)

    assert {:ok, %{written: ["tests.structured"]}} =
             Form.save(%{"tests.structured" => ~s({"local":"/private"})}, fields, nil)

    assert Settings.get("tests.structured") == %{"local" => "/private"}

    assert {:ok, %{written: ["tests.structured"]}} =
             Form.save(%{"tests.structured" => ~s(["image/png","application/pdf"])}, fields, nil)

    assert Settings.get("tests.structured") == ["image/png", "application/pdf"]
  end

  test "invalid JSON and scalars refuse the write without changing the value" do
    Settings.put("tests.structured", %{"local" => "/private"})

    for value <- ["local=/private", "true", "42", ~s("text")] do
      assert {:error, "tests.structured", "must be a JSON object or array"} =
               Form.save(%{"tests.structured" => value}, Form.fields(["test"], nil), nil)

      assert Settings.get("tests.structured") == %{"local" => "/private"}
    end
  end
end
