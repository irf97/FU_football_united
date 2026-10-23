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
    unrelated = event(player_fixture(), %{title: "Unrelated"})
    {:ok, _} = Hobbies.join(mine.id, guest)
    {:ok, _} = Hobbies.cancel(mine.id, host, "Room closed")
    assert %{entries: [public_event]} = Hobbies.discover(%{}, guest)
    assert public_event.id == unrelated.id

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

  test "aliases retrieve relevant hobbies ahead of incidental title and place mentions" do
    host = player_fixture()
    title = event(host, %{title: "Ping pong painting", hobby: "painting"})
    place = event(host, %{title: "Quiet sketching", hobby: "drawing", place: "Table Tennis Hall"})
    hobby = event(host, %{title: "One more rally", hobby: "table tennis"})

    result = Hobbies.discover(%{q: "I want to play ping pong"}, host)
    assert Enum.map(result.entries, & &1.id) == [hobby.id, title.id, place.id]
  end

  test "each term must match the same activity and explicit filters remain hard constraints" do
    host = player_fixture()
    rally = event(host, %{title: "One more rally", hobby: "table tennis", category: "sport"})
    event(host, %{title: "One more rally", hobby: "table tennis", place: "River room"})
    event(host, %{title: "River walk", hobby: "walking", category: "outdoors"})

    assert %{entries: [%{id: id}]} =
             Hobbies.discover(%{q: "tafeltennis campus", category: "sport", space: true}, host)

    assert id == rally.id
    assert %{entries: []} = Hobbies.discover(%{q: "tafeltennis", category: "music"}, host)
    assert %{entries: []} = Hobbies.discover(%{q: "tafeltennis campus river"}, host)
    for _ <- 1..2, do: {:ok, _} = Hobbies.join(rally.id, player_fixture())
    assert %{entries: []} = Hobbies.discover(%{q: "tafeltennis campus", space: true}, host)
  end

  test "ranked search still limits closed history to persisted membership" do
    host = player_fixture()
    guest = player_fixture()
    mine = event(host, %{title: "One more rally", hobby: "table tennis"})
    other_host = player_fixture()
    other = event(other_host, %{title: "Private past rally", hobby: "table tennis"})
    {:ok, _} = Hobbies.join(mine.id, guest)
    {:ok, _} = Hobbies.cancel(mine.id, host, "Room closed")
    {:ok, _} = Hobbies.cancel(other.id, other_host, "Room closed")

    assert %{entries: []} = Hobbies.discover(%{q: "ping pong"}, guest)
    assert %{entries: [%{id: id}]} = Hobbies.discover(%{q: "ping pong", scope: "mine"}, guest)
    assert id == mine.id
    assert %{entries: []} = Hobbies.discover(%{q: "ping pong", scope: "mine"}, player_fixture())
  end

  test "relevance ordering happens before pagination" do
    host = player_fixture()
    for _ <- 1..25, do: event(host, %{title: "Guitar decoration", hobby: "painting"})
    best = event(host, %{title: "Late acoustic circle"})
    assert %{entries: [first | rest], more?: true} = Hobbies.discover(%{q: "gitaar"}, host)
    assert first.id == best.id
    assert length(rest) == 23
    assert %{entries: last_page, more?: false} = Hobbies.discover(%{q: "gitaar", page: 2}, host)
    assert length(last_page) == 2
    refute Enum.any?(last_page, &(&1.id == best.id))
  end

  test "unknown hobbies remain searchable and unsupported requests do not become broad matches" do
    host = player_fixture()
    astronomy = event(host, %{title: "Listen to the sky", hobby: "amateur radio astronomy"})
    event(host, %{})
    assert %{entries: [%{id: id}]} = Hobbies.discover(%{q: "amateur radio astronomy"}, host)
    assert id == astronomy.id
    assert %{entries: []} = Hobbies.discover(%{q: "guitar without equipment tonight"}, host)
    assert %{entries: []} = Hobbies.discover(%{q: "guitar%' OR 1=1 --"}, host)
  end
end
