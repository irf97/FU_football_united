defmodule Fu.Hobbies do
  @moduledoc """
  Shared hobby sessions, explicit commitments and recoverable participation.

  Every mutation locks its session row. Capacity checks, participant changes
  and the durable event record commit together. PubSub is a refresh hint;
  a reconnect always reads the authoritative database state.
  Venue access is a host declaration, never an automatic booking claim.
  """
  import Ecto.Query
  alias Fu.Repo
  alias Fu.Accounts.Player
  alias Fu.Hobbies.{Session, Participant, Event, Rules}

  @present ["joined", "committed", "attended"]

  def subscribe, do: Phoenix.PubSub.subscribe(Fu.PubSub, "hobbies")
  def subscribe(id), do: Phoenix.PubSub.subscribe(Fu.PubSub, "hobby_session:#{id}")

  def create_session(%Player{} = host, attrs) do
    changeset = Session.creation_changeset(%Session{host_id: host.id}, attrs)

    case Repo.transaction(fn ->
           case Repo.insert(changeset) do
             {:ok, session} ->
               record!(session.id, host.id, "created", %{hobby: session.hobby, mode: session.mode})

               session

             {:error, changeset} ->
               Repo.rollback(changeset)
           end
         end) do
      {:ok, session} ->
        broadcast(session.id)
        {:ok, session}

      error ->
        error
    end
  end

  def change_session(attrs \\ %{}), do: Session.creation_changeset(%Session{}, attrs)

  @doc "Discover bounded pages of events; a person's own history is scoped by persisted membership."
  def discover(params, %Player{} = player) do
    filters = Fu.Hobbies.Discovery.normalize(params)
    query = from(s in Session)

    query =
      if filters.scope == "mine" do
        memberships =
          from(p in Participant, where: p.player_id == ^player.id, select: p.session_id)

        from(s in query,
          where: s.host_id == ^player.id or s.id in subquery(memberships),
          order_by: [desc: s.starts_at, desc: s.id]
        )
      else
        from(s in query,
          where: s.status in ["scheduled", "active"] and s.ends_at > ^now(),
          order_by: [asc: s.starts_at, asc: s.id]
        )
      end

    query =
      Enum.reduce([:hobby, :category, :kind, :mode], query, fn key, query ->
        case Map.fetch!(filters, key) do
          "" -> query
          value -> from(s in query, where: field(s, ^key) == ^value)
        end
      end)

    query =
      if filters.q == "" do
        query
      else
        term = String.downcase(filters.q)

        from(s in query,
          where:
            fragment("strpos(lower(?), ?) > 0", s.title, ^term) or
              fragment("strpos(lower(?), ?) > 0", s.hobby, ^term) or
              fragment("strpos(lower(?), ?) > 0", s.place, ^term)
        )
      end

    query =
      if filters.place == "" do
        query
      else
        term = String.downcase(filters.place)
        from(s in query, where: fragment("strpos(lower(?), ?) > 0", s.place, ^term))
      end

    query =
      if filters.space do
        counts =
          from(p in Participant,
            where: p.status in ^@present,
            group_by: p.session_id,
            select: %{session_id: p.session_id, occupied: count(p.id)}
          )

        from(s in query,
          left_join: c in subquery(counts),
          on: c.session_id == s.id,
          where: coalesce(c.occupied, 0) < s.capacity
        )
      else
        query
      end

    entries = query |> limit(25) |> offset(^((filters.page - 1) * 24)) |> Repo.all()

    %{
      entries: entries |> Enum.take(24) |> Repo.preload([:host, participants: :player]),
      more?: length(entries) > 24
    }
  end

  def hobby_catalog do
    from(s in Session,
      where: s.status in ["scheduled", "active"] and s.ends_at > ^now(),
      group_by: s.hobby,
      order_by: s.hobby,
      limit: 80,
      select: %{name: s.hobby, count: count(s.id)}
    )
    |> Repo.all()
  end

  def list_sessions(filters \\ %{}) do
    query = from(s in Session, order_by: [asc: s.starts_at, asc: s.id])

    query =
      if Map.get(filters, :include_closed, false) do
        query
      else
        from(s in query, where: s.status in ["scheduled", "active"] and s.ends_at > ^now())
      end

    query =
      case Map.get(filters, :hobby) do
        hobby when is_binary(hobby) and hobby != "" ->
          from(s in query, where: s.hobby == ^String.downcase(String.trim(hobby)))

        _ ->
          query
      end

    query |> Repo.all() |> Repo.preload([:host, participants: :player])
  end

  def get_session(id) do
    case valid_id(id) do
      nil -> nil
      id -> Repo.get(Session, id) |> Repo.preload([:host, participants: :player])
    end
  end

  def history(id) do
    case valid_id(id) do
      nil ->
        []

      id ->
        Repo.all(
          from(e in Event, where: e.session_id == ^id, order_by: [asc: e.id], preload: [:actor])
        )
    end
  end

  def occupied(session), do: Enum.count(session.participants, &(&1.status in @present))

  def membership(session, %Player{id: id}),
    do: Enum.find(session.participants, &(&1.player_id == id))

  def join(id, %Player{} = player) do
    mutate(id, player, fn session, at ->
      membership = participant(session.id, player.id)

      if membership && membership.status in @present do
        {:unchanged, membership}
      else
        count =
          Repo.aggregate(
            from(p in Participant, where: p.session_id == ^session.id and p.status in ^@present),
            :count
          )

        case Rules.join_error(session, count, at) do
          nil ->
            membership = membership || %Participant{session_id: session.id, player_id: player.id}

            changeset =
              Ecto.Changeset.change(membership,
                status: "joined",
                committed_at: nil,
                attended_at: nil,
                left_at: nil,
                withdrawal_reason: nil
              )

            {:ok, Repo.insert_or_update!(changeset), "joined", %{}}

          error ->
            {:error, error}
        end
      end
    end)
  end

  def commit(id, %Player{} = player) do
    mutate(id, player, fn session, at ->
      cond do
        session.mode != "committed" ->
          {:error, :not_required}

        DateTime.compare(at, session.ends_at) != :lt ->
          {:error, :expired}

        true ->
          case participant(session.id, player.id) do
            %Participant{status: status} = member when status in ["committed", "attended"] ->
              {:unchanged, member}

            %Participant{status: "joined"} = member ->
              {:ok,
               member
               |> Ecto.Changeset.change(status: "committed", committed_at: at)
               |> Repo.update!(), "committed", %{}}

            _ ->
              {:error, :not_joined}
          end
      end
    end)
  end

  def leave(id, %Player{} = player, reason \\ "") do
    mutate(id, player, fn session, at ->
      case participant(session.id, player.id) do
        nil ->
          {:error, :not_joined}

        %Participant{status: "left"} = member ->
          {:unchanged, member}

        member ->
          case Rules.withdrawal_error(member, reason) do
            nil ->
              reason = String.trim(reason)

              {:ok,
               member
               |> Ecto.Changeset.change(
                 status: "left",
                 left_at: at,
                 withdrawal_reason: blank_to_nil(reason)
               )
               |> Repo.update!(), "left",
               %{reason: reason, was_committed: member.committed_at != nil}}

            error ->
              {:error, error}
          end
      end
    end)
  end

  def confirm_access(id, %Player{} = host, note) do
    mutate(id, host, fn session, _at ->
      with :ok <- host_only(session, host), :ok <- require_reason(note) do
        {:ok,
         session
         |> Ecto.Changeset.change(access_status: "host_confirmed", access_note: String.trim(note))
         |> Repo.update!(), "access_confirmed",
         %{note: String.trim(note), source: "host_declaration"}}
      end
    end)
  end

  def start(id, %Player{} = host) do
    mutate(id, host, fn session, at ->
      with :ok <- host_only(session, host) do
        if session.status == "active" do
          {:unchanged, session}
        else
          members = Repo.all(from(p in Participant, where: p.session_id == ^session.id))

          case Rules.start_error(session, members, at) do
            nil -> {:ok, set_status!(session, "active"), "started", %{}}
            error -> {:error, error}
          end
        end
      end
    end)
  end

  def attend(id, %Player{} = player) do
    mutate(id, player, fn session, at ->
      cond do
        session.status != "active" ->
          {:error, :not_active}

        DateTime.compare(at, session.ends_at) != :lt ->
          {:error, :expired}

        true ->
          case participant(session.id, player.id) do
            %Participant{status: "attended"} = member ->
              {:unchanged, member}

            %Participant{status: status} = member when status in ["joined", "committed"] ->
              if session.mode == "committed" and member.committed_at == nil do
                {:error, :commit_first}
              else
                {:ok,
                 member
                 |> Ecto.Changeset.change(status: "attended", attended_at: at)
                 |> Repo.update!(), "attended", %{source: "self_check_in"}}
              end

            _ ->
              {:error, :not_joined}
          end
      end
    end)
  end

  def finish(id, %Player{} = host) do
    mutate(id, host, fn session, _at ->
      with :ok <- host_only(session, host) do
        if session.status == "active",
          do: {:ok, set_status!(session, "completed"), "completed", %{}},
          else: {:error, :not_active}
      end
    end)
  end

  def cancel(id, %Player{} = host, reason) do
    mutate(id, host, fn session, at ->
      with :ok <- host_only(session, host), :ok <- require_reason(reason) do
        cancelled =
          session
          |> Ecto.Changeset.change(status: "cancelled", cancellation_reason: String.trim(reason))
          |> Repo.update!()

        Repo.update_all(
          from(p in Participant, where: p.session_id == ^session.id and p.status in ^@present),
          set: [status: "cancelled", updated_at: at]
        )

        {:ok, cancelled, "cancelled", %{reason: String.trim(reason)}}
      end
    end)
  end

  defp mutate(id, player, action) do
    case valid_id(id) do
      nil ->
        {:error, :not_found}

      id ->
        result =
          Repo.transaction(fn ->
            session = Repo.one(from(s in Session, where: s.id == ^id, lock: "FOR UPDATE"))

            cond do
              session == nil ->
                Repo.rollback(:not_found)

              session.status in ["cancelled", "completed"] ->
                Repo.rollback(:closed)

              true ->
                case action.(session, now()) do
                  {:ok, value, event, payload} ->
                    record!(id, player.id, event, payload)
                    {value, true}

                  {:unchanged, value} ->
                    {value, false}

                  {:error, reason} ->
                    Repo.rollback(reason)
                end
            end
          end)

        case result do
          {:ok, {value, changed?}} ->
            if changed?, do: broadcast(id)
            {:ok, value}

          error ->
            error
        end
    end
  end

  defp participant(session_id, player_id),
    do: Repo.get_by(Participant, session_id: session_id, player_id: player_id)

  defp set_status!(session, status),
    do: session |> Ecto.Changeset.change(status: status) |> Repo.update!()

  defp host_only(%{host_id: id}, %{id: id}), do: :ok
  defp host_only(_, _), do: {:error, :forbidden}

  defp require_reason(reason) when is_binary(reason) do
    cond do
      String.trim(reason) == "" -> {:error, :reason_required}
      String.length(reason) > 500 -> {:error, :reason_too_long}
      true -> :ok
    end
  end

  defp require_reason(_), do: {:error, :reason_required}
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
  defp valid_id(id) when is_integer(id) and id > 0 and id <= 9_223_372_036_854_775_807, do: id

  defp valid_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {id, ""} -> valid_id(id)
      _ -> nil
    end
  end

  defp valid_id(_), do: nil

  defp record!(session_id, actor_id, action, payload) do
    Repo.insert!(%Event{
      session_id: session_id,
      actor_id: actor_id,
      action: action,
      payload: payload
    })
  end

  defp broadcast(id) do
    Phoenix.PubSub.broadcast(Fu.PubSub, "hobbies", {:hobby_session_changed, id})
    Phoenix.PubSub.broadcast(Fu.PubSub, "hobby_session:#{id}", {:hobby_session_changed, id})
  end
end
