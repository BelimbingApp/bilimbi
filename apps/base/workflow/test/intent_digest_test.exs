defmodule Bilimbi.Base.Workflow.IntentDigestTest do
  use ExUnit.Case, async: true
  alias Bilimbi.Base.Workflow.IntentDigest

  # Canonical strings and digests produced by PHP 8.5 `json_encode` (default
  # flags) and `hash('sha256', ...)` over Belimbing's intentHash sorting:
  # recursive ksort of associative arrays with list order preserved
  # (HumanActionService.php:216-235). Generic fixtures; CI needs no PHP.

  test "a legacy alias intent reproduces PHP escaping, key order, empty arrays and surrogates" do
    intent = %{
      subject_type: "Legacy\\Example\\Record",
      subject_id: "41",
      actor_type: "user",
      actor_id: 7,
      action_key: "example.approve",
      process_run_id: nil,
      work_item_id: nil,
      payload: %{
        "comment" => "Looks good / ok",
        "score" => "9.5",
        "tags" => ["b", "a"],
        "unicode" => "ü 😀 \u2028x",
        "nested" => %{"z" => true, "a" => %{"empty" => %{}}},
        "quote" => "He said \"hi\"\n\t<>&'\\",
        "flag" => false,
        "none" => nil,
        "count" => 3
      }
    }

    assert {:ok, json} = IntentDigest.canonical(intent)

    assert json ==
             ~S|{"action_key":"example.approve","actor_id":7,"actor_type":"user","payload":{"comment":"Looks good \/ ok","count":3,"flag":false,"nested":{"a":{"empty":[]},"z":true},"none":null,"quote":"He said \"hi\"\n\t<>&'\\","score":"9.5","tags":["b","a"],"unicode":"\u00fc \ud83d\ude00 \u2028x"},"process_run_id":null,"subject_id":"41","subject_type":"Legacy\\Example\\Record","work_item_id":null}|

    assert IntentDigest.digest(intent) ==
             {:ok, "601c9e0560436bce8e6617470a2aaf636db0017a2866be1a0b4aa8723003bbdc"}
  end

  test "work binding, an empty payload and control characters match PHP" do
    work = %{
      subject_type: "example.record",
      subject_id: "41",
      actor_type: "user",
      actor_id: 7,
      action_key: "example.first",
      process_run_id: 12,
      work_item_id: 34,
      payload: %{"note" => "done"}
    }

    assert IntentDigest.canonical(work) ==
             {:ok,
              ~S|{"action_key":"example.first","actor_id":7,"actor_type":"user","payload":{"note":"done"},"process_run_id":12,"subject_id":"41","subject_type":"example.record","work_item_id":34}|}

    assert IntentDigest.digest(work) ==
             {:ok, "61601c8ef7cbff6629c00df144476dedb699019c8a521bf13dd92acccdf06fac"}

    empty = %{
      work
      | action_key: "example.approve",
        process_run_id: nil,
        work_item_id: nil,
        payload: %{}
    }

    assert IntentDigest.canonical(empty) ==
             {:ok,
              ~S|{"action_key":"example.approve","actor_id":7,"actor_type":"user","payload":[],"process_run_id":null,"subject_id":"41","subject_type":"example.record","work_item_id":null}|}

    assert IntentDigest.digest(empty) ==
             {:ok, "ad3ae5828c3cd2036f5a53d2cc857e944220cf3a5687a7c2ada528529de55157"}

    assert IntentDigest.digest(%{empty | payload: []}) == IntentDigest.digest(empty)

    control = %{
      empty
      | subject_id: "7",
        actor_id: 1,
        action_key: "a.b",
        payload: %{"c" => <<1, 0x1F, 0x7F, "é€">>}
    }

    assert IntentDigest.canonical(control) ==
             {:ok,
              ~S|{"action_key":"a.b","actor_id":1,"actor_type":"user","payload":{"c":"\u0001\u001f| <>
                <<0x7F>> <>
                ~S|\u00e9\u20ac"},"process_run_id":null,"subject_id":"7","subject_type":"example.record","work_item_id":null}|}

    assert IntentDigest.digest(control) ==
             {:ok, "1660d6f17a11ca644a4f6ce436eca8013d211d85a52dc2a38b2abc865427d13a"}
  end

  test "values PHP serializes differently are refused instead of hashed differently" do
    for payload <- [
          %{"score" => 9.5},
          %{"ratio" => [1.0]},
          %{"12" => "x"},
          %{" 1e3 " => "x"},
          %{".5" => "x"},
          %{"-0" => "x"},
          %{"text" => <<0xFF>>},
          %{"when" => ~D[2026-01-01]},
          %{"nested" => %{atom: 1}},
          {:tuple}
        ] do
      refute IntentDigest.reproducible?(payload), inspect(payload)
    end

    assert IntentDigest.reproducible?(%{"0x1a" => 1, "12abc" => 2, "" => [nil, true, %{}]})

    assert IntentDigest.encode(%{"b" => 1, "a" => [%{"d" => 2, "c" => 3}]}) ==
             {:ok, ~S|{"a":[{"c":3,"d":2}],"b":1}|}
  end
end
