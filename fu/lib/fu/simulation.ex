defmodule Fu.Simulation do
  @moduledoc "An additive fictional setting, restricted to explicitly isolated simulation databases."
  import Ecto.Query
  alias Fu.{Accounts, Assistant, Equipment, Hobbies, Repo}
  alias Fu.Accounts.Player
  alias Fu.Hobbies.Session
  alias Fu.Equipment.{Asset, Observation}

  @people ~w(Ari Noor Bo Remy Sky Jules Deniz Robin Mika Sasha Alex Eden)
  @setting [
    {"Commons six-a-side", "futsal", "sport", "committed", "Commons Court", "Football kit bag",
     "goals"},
    {"One more rally", "table tennis", "sport", "open", "The Long Table", "Table tennis kit",
     "points"},
    {"Acoustic after hours", "guitar", "music", "practice", "Listening Room", "Guitar case", nil},
    {"Take the long way", "walking", "outdoors", "open", "River Gate", "Hiking daypack", nil},
    {"Make a pedal", "electronics", "making", "practice", "Maker Loft", "Maker box", nil},
    {"Sunset pickup", "basketball", "sport", "open", "West Court", "Basketball kit bag", "points"}
  ]

  def seed! do
    isolated!()

    {:ok, result} =
      Repo.transaction(fn ->
        Repo.query!("SELECT pg_advisory_xact_lock(hashtext('spontaan-commons-v1'))")
        people = Enum.with_index(@people, 1) |> Enum.map(fn {name, i} -> person!(name, i) end)
        [host | guests] = people
        at = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(7200)

        sessions =
          Enum.with_index(@setting, 1)
          |> Enum.map(fn {{title, hobby, category, mode, place, gear, unit}, i} ->
            case Repo.get_by(Session, host_id: host.id, title: title) do
              nil ->
                {:ok, session} =
                  Hobbies.create_session(host, %{
                    title: title,
                    hobby: hobby,
                    category: category,
                    kind: "session",
                    mode: mode,
                    place: place,
                    starts_at: DateTime.add(at, i * 900),
                    ends_at: DateTime.add(at, i * 900 + 3600),
                    capacity: 12,
                    min_participants: 2
                  })

                {:ok, _} =
                  Hobbies.confirm_access(session.id, host, "Spontaan Commons fictional venue")

                for person <- Enum.take(guests, 3) do
                  {:ok, _} = Hobbies.join(session.id, person)
                  if mode == "committed", do: Hobbies.commit(session.id, person)
                end

                asset = asset!(host, hobby, gear, place, i)
                {:ok, _} = Equipment.reserve(asset.id, session.id, host)

                if unit do
                  {:ok, _} =
                    Assistant.configure(session.id, host, %{
                      team_a: "Commons",
                      team_b: "Visitors",
                      unit: unit,
                      duration_seconds: 1200,
                      referee_id: hd(guests).id
                    })
                end

                session.id

              session ->
                session.id
            end
          end)

        %{setting: "Spontaan Commons", players: Enum.map(people, & &1.id), sessions: sessions}
      end)

    result
  end

  defp person!(name, index) do
    phone = "+316800006" <> String.pad_leading(to_string(index), 2, "0")

    Repo.get_by(Player, phone: phone) ||
      case %Player{}
           |> Player.registration_changeset(%{phone: phone, display_name: name})
           |> Repo.insert() do
        {:ok, person} ->
          {_, hobby, _, _, _, _, _} = Enum.at(@setting, rem(index - 1, length(@setting)))

          {:ok, person} =
            Accounts.update_experience(person, %{main_hobby: hobby, experience_theme: "auto"})

          person
      end
  end

  defp asset!(host, hobby, name, zone, index) do
    beacon = "commons-gear-#{index}"
    asset = Repo.get_by(Asset, owner_id: host.id, beacon_id: beacon)

    asset =
      asset ||
        case Equipment.create_asset(host, %{
               name: name,
               hobby: hobby,
               beacon_id: beacon,
               home_zone: "Commons gear wall"
             }) do
          {:ok, asset} -> asset
        end

    unless Repo.exists?(from(o in Observation, where: o.asset_id == ^asset.id)) do
      {:ok, receiver, token} =
        Equipment.create_receiver(host, %{name: "Commons #{index}", zone: zone})

      {:ok, _} =
        Equipment.ingest(token, %{
          "beacon_id" => beacon,
          "message_id" => "commons-initial-#{index}",
          "observed_at" => DateTime.to_iso8601(DateTime.utc_now() |> DateTime.truncate(:second)),
          "rssi" => -58
        })

      {:ok, _} = Equipment.revoke_receiver(receiver.id, host)
    end

    asset
  end

  defp isolated! do
    unless Application.get_env(:fu, :environment) == :rehearsal,
      do: raise("Commons requires an isolated simulation database and rehearsal mode")

    %{rows: [[database]]} = Repo.query!("SELECT current_database()")

    unless database in ["fu_test", "fu_pilot_qa", "spontaan_simulation"],
      do: raise("Commons requires an isolated simulation database")
  end
end
