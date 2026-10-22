defmodule Fu.Hobbies.ExploreTest do
  use Fu.DataCase, async: true
  alias Fu.Hobbies

  defp event(host, extra) do
    at = DateTime.utc_now() |> DateTime.add(3600) |> DateTime.truncate(:second)

    {:ok, session} =
      Hobbies.create_session(
        host,
        Map.merge(
          %{
            title: "Guitar in the garden",
            hobby: "guitar",
            category: "music",
            kind: "meetup",
            mode: "open",
            place: "Campus garden",
            starts_at: at,
            ends_at: DateTime.add(at, 3600),
            capacity: 2,
            min_participants: 1
          },
          extra
        )
      )

    session
  end

  test "explore combines literal search, category, event kind and space filters" do
    host = player_fixture()
    music = event(host, %{})

    event(host, %{
      title: "Make a tiny telescope",
      hobby: "astronomy",
      category: "making",
      kind: "class"
    })

    assert %{entries: [%{id: id}]} =
             Hobbies.discover(%{"q" => "garden", "category" => "music", "kind" => "meetup"}, host)

    assert id == music.id
    assert %{entries: []} = Hobbies.discover(%{"q" => "%"}, host)
    for _ <- 1..2, do: {:ok, _} = Hobbies.join(music.id, player_fixture())
    assert %{entries: [remaining]} = Hobbies.discover(%{"space" => "true"}, host)
    assert remaining.hobby == "astronomy"
  end

  test "my events includes persisted history and excludes unrelated activity" do
    host = player_fixture()
    guest = player_fixture()
    mine = event(host, %{})
    event(player_fixture(), %{title: "Unrelated"})
    {:ok, _} = Hobbies.join(mine.id, guest)
    {:ok, _} = Hobbies.cancel(mine.id, host, "Room closed")
    assert %{entries: []} = Hobbies.discover(%{}, guest)

    assert %{entries: [%{id: id, status: "cancelled"}]} =
             Hobbies.discover(%{"scope" => "mine"}, guest)

    assert id == mine.id
    assert %{entries: []} = Hobbies.discover(%{"scope" => "mine"}, player_fixture())
  end

  test "catalog contains actual available hobbies and query pages are bounded" do
    host = player_fixture()
    event(host, %{})
    event(host, %{hobby: "experimental pottery"})
    assert Enum.map(Hobbies.hobby_catalog(), & &1.name) == ["experimental pottery", "guitar"]
    assert %{entries: [], more?: false} = Hobbies.discover(%{"page" => "99999"}, host)
  end
end
