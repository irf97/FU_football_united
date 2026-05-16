defmodule Fu.Fixtures do
  @moduledoc "Flat factory helpers for tests (no ExMachina)."

  alias Fu.Repo
  alias Fu.Accounts.Player
  alias Fu.Queues
  alias Fu.Queues.QueueMembership

  @doc "A player. opts: :phone, :display_name, :rank, :primary_position, :is_admin."
  def player_fixture(opts \\ %{}) do
    opts = Map.new(opts)
    n = System.unique_integer([:positive])
    phone = opts[:phone] || "+3161#{String.pad_leading("#{rem(n, 100_000_000)}", 8, "0")}"

    {:ok, p} =
      %Player{}
      |> Player.registration_changeset(%{phone: phone})
      |> Repo.insert()

    p
    |> Ecto.Changeset.change(
      display_name: opts[:display_name] || "P#{n}",
      rank: opts[:rank] || 50.0,
      primary_position: opts[:primary_position] || "MID",
      secondary_position: opts[:secondary_position] || "FWD",
      is_admin: Map.get(opts, :is_admin, false)
    )
    |> Repo.update!()
  end

  def field_fixture(opts \\ %{}) do
    opts = Map.new(opts)

    {:ok, f} =
      Fu.Fields.create_field(%{
        name: opts[:name] || "Field #{System.unique_integer([:positive])}",
        operator_name: opts[:operator_name] || "Op",
        lat: opts[:lat] || 52.22,
        lng: opts[:lng] || 6.89,
        region: opts[:region] || "Enschede",
        formats: opts[:formats] || ~w(5v5 7v7 8v8 11v11)
      })

    f
  end

  @doc """
  A queue. opts:
    * :format (default "8v8") · :region · :scheduled_in (seconds from now,
      default 7200 — inside the 3h lock window so the Resolver picks it up)
    * :fill — `:all` (every slot filled) or an integer count of "MID" joiners
    * :state — override state after creation
  """
  def queue_fixture(opts \\ %{}) do
    opts = Map.new(opts)
    field = opts[:field] || field_fixture()
    format = opts[:format] || "8v8"
    secs = Map.get(opts, :scheduled_in, 7200)
    at = DateTime.utc_now() |> DateTime.add(secs, :second) |> DateTime.truncate(:second)

    {:ok, queue} =
      Queues.create_queue(%{
        field_id: field.id,
        format: format,
        scheduled_at: at,
        region: opts[:region] || "Enschede"
      })

    queue =
      case opts[:fill] do
        :all -> fill_all(queue)
        n when is_integer(n) -> add_members(queue, n, "MID")
        _ -> queue
      end

    if s = opts[:state] do
      queue |> Fu.Queues.Queue.changeset(%{state: s}) |> Repo.update!()
    end

    Queues.get_queue!(queue.id)
  end

  @doc "Inserts exactly enough queued members to satisfy every position quota."
  def fill_all(queue) do
    quotas = Fu.Positions.quotas(queue.formation)

    for {pos, cap} <- quotas, _i <- 1..cap do
      member(queue, player_fixture(primary_position: pos), pos)
    end

    Queues.get_queue!(queue.id)
  end

  def add_members(queue, n, pos) do
    for _ <- 1..n, do: member(queue, player_fixture(primary_position: pos), pos)
    Queues.get_queue!(queue.id)
  end

  def member(queue, player, pos, status \\ "queued") do
    {:ok, m} =
      %QueueMembership{}
      |> QueueMembership.changeset(%{
        queue_id: queue.id,
        player_id: player.id,
        declared_position: pos,
        status: status
      })
      |> Repo.insert()

    m
  end
end
