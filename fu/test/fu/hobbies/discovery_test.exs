defmodule Fu.Hobbies.DiscoveryTest do
  use ExUnit.Case, async: true
  alias Fu.Hobbies.{Discovery, Session}

  test "filters are bounded and never turn arbitrary input into atoms" do
    f =
      Discovery.normalize(%{
        "q" => "  music  ",
        "hobby" => " GUITAR ",
        "category" => "music",
        "kind" => "event",
        "mode" => "practice",
        "scope" => "mine",
        "space" => "true",
        "page" => "2"
      })

    assert f.q == "music"
    assert f.hobby == "guitar"
    assert f.category == "music"
    assert f.kind == "event"
    assert f.mode == "practice"
    assert f.scope == "mine"
    assert f.space
    assert f.page == 2

    invalid =
      Discovery.normalize(%{
        "q" => String.duplicate("a", 1000),
        "category" => "unknown",
        "kind" => "unknown",
        "mode" => "ranked",
        "scope" => "admin",
        "page" => "-9"
      })

    assert String.length(invalid.q) == 120
    assert invalid.category == ""
    assert invalid.kind == ""
    assert invalid.mode == ""
    assert invalid.scope == "all"
    assert invalid.page == 1
    assert Discovery.normalize(%{"q" => %{}, "page" => ["9"]}) == Discovery.normalize(%{})
  end

  test "hobbies remain open-ended while event metadata is validated" do
    at = DateTime.utc_now() |> DateTime.add(3600) |> DateTime.truncate(:second)

    attrs = %{
      title: "Radio astronomy evening",
      hobby: "amateur radio astronomy",
      category: "learning",
      kind: "event",
      mode: "open",
      place: "Campus room",
      starts_at: at,
      ends_at: DateTime.add(at, 3600),
      capacity: 8,
      min_participants: 1
    }

    cs = Session.creation_changeset(%Session{host_id: 1}, attrs)
    assert cs.valid?
    assert Ecto.Changeset.get_field(cs, :category) == "learning"
    assert Ecto.Changeset.get_field(cs, :kind) == "event"

    refute Session.creation_changeset(
             %Session{},
             Map.merge(attrs, %{category: "bad", kind: "bad"})
           ).valid?
  end

  test "URL parameters round-trip without internal or arbitrary fields" do
    f =
      Discovery.normalize(%{
        "q" => "guitar",
        "category" => "music",
        "page" => "3",
        "scope" => "mine",
        "admin" => "true"
      })

    params = Discovery.params(f)
    assert Discovery.normalize(params) == f
    refute Map.has_key?(params, "admin")
  end
end
