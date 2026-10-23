defmodule Fu.Hobbies.SearchTest do
  use ExUnit.Case, async: true
  alias Fu.Hobbies.Search

  test "English and Dutch phrases resolve to the same activity without a closed hobby catalog" do
    assert Search.labels("I want to play ping-pong at Commons") == ["table tennis", "commons"]
    assert Search.labels("Ik wil graag tafeltennis bij Commons") == ["table tennis", "commons"]
    assert Search.labels("gitaar guitar") == ["guitar"]
    assert Search.labels("amateur radio astronomy") == ["amateur", "radio", "astronomy"]
  end

  test "negations, alternatives and unsupported constraints are not silently removed" do
    assert Search.labels("not football") == ["not", "football"]

    assert Search.labels("guitar without equipment tonight") == [
             "guitar",
             "without",
             "equipment",
             "tonight"
           ]

    assert Search.labels("guitar or drums") == ["guitar", "or", "drums"]
  end

  test "punctuation and stopword-only requests retain a literal fallback" do
    assert Search.labels("%") == ["%"]
    assert Search.labels("the") == ["the"]
    assert Search.labels("  ") == []
    assert Search.labels(%{}) == []
    assert Search.labels(String.duplicate("z", 500)) == [String.duplicate("z", 120)]
  end

  test "explanations identify the actual matching field and prefer hobby over incidental mentions" do
    session = %{hobby: "table tennis", title: "Table tennis practice", place: "Commons Court"}

    assert Search.reasons(session, "ping pong Commons") == [
             "table tennis · hobby",
             "commons · place"
           ]

    assert Search.reasons(session, "missing") == []
  end
end
