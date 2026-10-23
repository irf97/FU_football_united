defmodule Fu.Assistant do
  @moduledoc """
  Event organization and optional human-controlled timing and scoring.
  Session locks serialize lifecycle, referee changes and score commands. Each accepted
  command has an optimistic revision, a retry key and an atomic, durable audit event.
  No automated physical adjudication, rank updates or disciplinary penalties occur.
  """
  import Ecto.Query
  alias Fu.{Repo, Hobbies, Equipment}
  alias Fu.Accounts.Player
  alias Fu.Hobbies.{Session, Participant}
  alias Fu.Assistant.{Board, Event, Rules}

  def change_board(attrs \\ %{}), do: Board.changeset(%Board{}, attrs)

  def snapshot(id, %Player{} = viewer) do
    case Hobbies.get_session(id) do
      nil ->
        nil

      session ->
        if member?(session, viewer) do
          board = Repo.get_by(Board, session_id: session.id) |> Repo.preload(:referee)
          assets = Equipment.session_assets(session, viewer)

          people =
            session.participants
            |> Enum.filter(&(&1.status in ["joined", "committed", "attended"]))
            |> Enum.map(&{&1.player.display_name, &1.player_id})

          options =
            Enum.uniq_by(
              [{session.host.display_name <> " · host", session.host_id} | people],
              &elem(&1, 1)
            )

          %{
            session: session,
            board: board,
            assets: assets,
            readiness: Rules.readiness(session, session.participants, assets, now()),
            clock: if(board, do: Rules.clock(board, now()), else: nil),
            referee_options: options,
            host?: session.host_id == viewer.id,
            can_officiate?: board && authorized?(session, board, viewer)
          }
        end
    end
  end

  def history(id, %Player{} = viewer) do
    case Hobbies.get_session(id) do
      nil ->
        []

      session ->
        if member?(session, viewer),
          do:
            Repo.all(
              from(e in Event,
                where: e.session_id == ^session.id,
                order_by: [desc: e.revision],
                limit: 100,
                preload: [:actor]
              )
            ),
          else: []
    end
  end

  def configure(id, %Player{} = host, attrs) do
    result =
      Repo.transaction(fn ->
        session = locked_session!(id)
        if session.host_id != host.id, do: Repo.rollback(:forbidden)
        if session.status not in ["scheduled", "active"], do: Repo.rollback(:closed)
        if Repo.get_by(Board, session_id: session.id), do: Repo.rollback(:already_configured)
        changeset = Board.changeset(%Board{session_id: session.id, referee_id: host.id}, attrs)
        referee = Ecto.Changeset.get_field(changeset, :referee_id)

        if changeset.valid? and not valid_referee?(session, referee),
          do: Repo.rollback(:invalid_referee)

        seconds = Ecto.Changeset.get_field(changeset, :duration_seconds)
        changeset = Ecto.Changeset.put_change(changeset, :remaining_seconds, seconds)

        board =
          case Repo.insert(changeset) do
            {:ok, board} -> board
            {:error, changeset} -> Repo.rollback(changeset)
          end

        record!(board, host, "configure", "configure", fingerprint("configure", host.id, %{}), %{
          "team_a" => board.team_a,
          "team_b" => board.team_b,
          "duration_seconds" => board.duration_seconds,
          "unit" => board.unit,
          "referee_id" => referee
        })

        board
      end)

    announce(result)
  end

  def command(id, %Player{} = actor, action, attrs) when is_map(attrs) and is_binary(action) do
    result =
      Repo.transaction(fn ->
        session = locked_session!(id)

        board =
          Repo.one(from(b in Board, where: b.session_id == ^session.id, lock: "FOR UPDATE")) ||
            Repo.rollback(:not_configured)

        unless authorized?(session, board, actor), do: Repo.rollback(:forbidden)
        request = attrs["request_id"]

        unless is_binary(request) and byte_size(request) in 1..80,
          do: Repo.rollback(:invalid_request)

        payload = Rules.command_payload(action, attrs)
        digest = fingerprint(action, actor.id, payload)
        previous = Repo.get_by(Event, session_id: session.id, request_id: request)

        cond do
          previous && previous.fingerprint == digest ->
            board

          previous ->
            Repo.rollback(:idempotency_conflict)

          integer(attrs["revision"]) != board.revision ->
            Repo.rollback(:stale_revision)

          true ->
            changes = changes!(session, board, actor, action, payload, now())

            next =
              Repo.update!(
                Ecto.Changeset.change(board, Map.put(changes, :revision, board.revision + 1))
              )

            payload =
              Map.merge(payload, %{
                "score_a" => next.score_a,
                "score_b" => next.score_b,
                "clock_status" => next.status,
                "remaining_seconds" => Rules.clock(next, now()).remaining_seconds
              })

            record!(next, actor, action, request, digest, payload)
            next
        end
      end)

    announce(result)
  end

  def command(_, _, _, _), do: {:error, :invalid_request}

  defp changes!(session, _board, host, "assign_referee", attrs, _) do
    if session.host_id != host.id, do: Repo.rollback(:forbidden)
    referee = integer(attrs["referee_id"])
    unless valid_referee?(session, referee), do: Repo.rollback(:invalid_referee)
    %{referee_id: referee}
  end

  defp changes!(session, board, _, "start", _, at) do
    active!(session)
    if board.status == "finalized", do: Repo.rollback(:finished)
    if board.status == "running", do: Repo.rollback(:already_running)
    if board.remaining_seconds <= 0, do: Repo.rollback(:elapsed)
    %{status: "running", deadline_at: DateTime.add(at, board.remaining_seconds)}
  end

  defp changes!(session, board, _, "pause", _, at) do
    active!(session)
    if board.status != "running", do: Repo.rollback(:not_running)

    %{
      status: "paused",
      deadline_at: nil,
      remaining_seconds: Rules.clock(board, at).remaining_seconds
    }
  end

  defp changes!(session, board, _, "score", attrs, _) do
    active!(session)
    if board.status == "finalized", do: Repo.rollback(:finished)
    unless board.status in ["running", "paused"], do: Repo.rollback(:not_running)
    side = attrs["side"]
    delta = integer(attrs["delta"])
    unless side in ["a", "b"] and delta in [-1, 1], do: Repo.rollback(:invalid_score)
    key = if side == "a", do: :score_a, else: :score_b
    value = Map.fetch!(board, key) + delta
    unless value in 0..99_999, do: Repo.rollback(:invalid_score)
    %{key => value}
  end

  defp changes!(session, _board, _, "correct", attrs, _) do
    reviewable!(session)
    reason!(attrs)
    a = integer(attrs["score_a"])
    b = integer(attrs["score_b"])

    unless is_integer(a) and a in 0..99_999 and is_integer(b) and b in 0..99_999,
      do: Repo.rollback(:invalid_score)

    %{score_a: a, score_b: b}
  end

  defp changes!(session, board, _, "finalize", attrs, at) do
    reviewable!(session)
    reason!(attrs)
    if board.status == "finalized", do: Repo.rollback(:finished)
    if board.status == "idle", do: Repo.rollback(:not_running)

    %{
      status: "finalized",
      deadline_at: nil,
      remaining_seconds: Rules.clock(board, at).remaining_seconds
    }
  end

  defp changes!(_, _, _, _, _, _), do: Repo.rollback(:invalid_command)

  defp reason!(attrs) do
    reason = attrs["reason"]

    unless is_binary(reason) and String.length(String.trim(reason)) in 3..500,
      do: Repo.rollback(:reason_required)
  end

  defp active!(%{status: "active"}), do: :ok
  defp active!(_), do: Repo.rollback(:not_active)
  defp reviewable!(%{status: status}) when status in ["active", "completed"], do: :ok
  defp reviewable!(_), do: Repo.rollback(:not_active)

  defp authorized?(session, board, player),
    do:
      session.host_id == player.id or (board.referee_id == player.id and member?(session, player))

  defp member?(session, player),
    do: session.host_id == player.id or current_member?(session.id, player.id)

  defp valid_referee?(session, id),
    do: is_integer(id) and (session.host_id == id or current_member?(session.id, id))

  defp current_member?(session_id, player_id),
    do:
      Repo.exists?(
        from(p in Participant,
          where:
            p.session_id == ^session_id and p.player_id == ^player_id and
              p.status in ["joined", "committed", "attended"]
        )
      )

  defp record!(board, actor, action, request, digest, payload),
    do:
      Repo.insert!(%Event{
        session_id: board.session_id,
        actor_id: actor.id,
        action: action,
        request_id: request,
        fingerprint: digest,
        revision: board.revision,
        payload: payload
      })

  defp announce({:ok, board} = result),
    do:
      (
        Hobbies.broadcast_change(board.session_id)
        result
      )

  defp announce(error), do: error

  defp fingerprint(action, actor_id, payload),
    do: :crypto.hash(:sha256, :erlang.term_to_binary({action, actor_id, payload}))

  defp locked_session!(id) do
    id = integer(id)

    unless is_integer(id) and id > 0 and id <= 9_223_372_036_854_775_807,
      do: Repo.rollback(:not_found)

    Repo.one(from(s in Session, where: s.id == ^id, lock: "FOR UPDATE")) ||
      Repo.rollback(:not_found)
  end

  defp integer(value) when is_integer(value), do: value

  defp integer(value) when is_binary(value) and byte_size(value) <= 19 do
    case Integer.parse(value) do
      {number, ""} -> number
      _ -> nil
    end
  end

  defp integer(_), do: nil
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
