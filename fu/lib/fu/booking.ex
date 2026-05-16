defmodule Fu.Booking do
  @moduledoc """
  Adaptive field booking (spec §2.3). The platform — not players — books the
  field, paying more as the queue fills:

      Speculative  queue created, hold placed, nothing paid
      Provisional  queue ≥80% full → deposit paid
      Confirmed    queue 100% full & ≥3h pre-kickoff → balance paid

  Empty/failed queues release the hold; on a partial-fail the deposit is
  forfeited (note in `reconcile/1`). Operator coordination goes through
  `Fu.Booking.OperatorStub` (manual, spec §5).
  """

  alias Fu.Repo
  alias Fu.Booking.{Booking, OperatorStub}
  alias Fu.Queues
  alias Fu.Queues.Queue

  @lock_seconds 3 * 3600

  @doc """
  Gets — or, on first call, creates — the speculative booking for `queue`.

  Creating one places the operator hold (spec §2.3 Speculative) and stores the
  returned `operator_ref`. Idempotent: subsequent calls return the existing
  booking untouched. Returns `{:ok, booking}`.
  """
  def ensure_booking(%Queue{} = queue) do
    case get_for_queue(queue.id) do
      %Booking{} = booking ->
        {:ok, booking}

      nil ->
        {:ok, ref} = OperatorStub.hold(queue.field, queue)

        %Booking{}
        |> Booking.changeset(%{
          queue_id: queue.id,
          field_id: queue.field_id,
          state: "speculative",
          operator_ref: ref
        })
        |> Repo.insert()
    end
  end

  @doc """
  The core adaptive transition (spec §2.3). Reads the queue's current
  `fill_ratio` + `seconds_to_kickoff` and advances the booking:

    * full (≥1.0), locked (≥3h pre-kickoff) and queue confirmed → `confirmed`
      (pays the balance if not yet paid)
    * ≥80% full → `provisional` (pays the deposit if not yet paid)
    * queue cancelled → `released` (releases the hold; any deposit already
      paid is **forfeited** — partial-fail penalty, spec §2.3)
    * otherwise → stays `speculative`

  Never regresses out of `confirmed`. Persists via changeset and returns
  `{:ok, booking}`.
  """
  def reconcile(%Queue{} = queue) do
    {:ok, booking} = ensure_booking(queue)

    ratio = Queues.fill_ratio(queue)
    to_kickoff = Queues.seconds_to_kickoff(queue)

    cond do
      # Once Confirmed the field is paid in full — never walk it back.
      booking.state == "confirmed" ->
        {:ok, booking}

      # Confirmed: queue 100% full, inside the 3h lock window, queue confirmed.
      ratio >= 1.0 and to_kickoff >= @lock_seconds and queue.state in ["confirmed"] ->
        booking
        |> maybe_pay(:balance, queue)
        |> transition("confirmed")

      # Cancelled queue: release the hold; deposit (if any) is forfeited.
      queue.state == "cancelled" ->
        :ok = OperatorStub.release(queue.field, queue)
        transition(booking, "released")

      # Provisional: queue ≥80% full → deposit committed.
      ratio >= 0.8 ->
        booking
        |> maybe_pay(:deposit, queue)
        |> transition("provisional")

      # Speculative: hold only, nothing paid.
      true ->
        transition(booking, "speculative")
    end
  end

  @doc "The booking for `queue_id`, or nil."
  def get_for_queue(queue_id), do: Repo.get_by(Booking, queue_id: queue_id)

  @doc "Convenience: the booking state as an atom, or `:none`."
  def state_for(%Queue{} = queue) do
    case get_for_queue(queue.id) do
      %Booking{state: s} -> String.to_atom(s)
      nil -> :none
    end
  end

  # Pays deposit/balance once (idempotent on the booking flag), recording the
  # latest operator_ref.
  defp maybe_pay(%Booking{deposit_paid: true} = b, :deposit, _queue), do: b
  defp maybe_pay(%Booking{balance_paid: true} = b, :balance, _queue), do: b

  defp maybe_pay(%Booking{} = b, :deposit, queue) do
    {:ok, ref} = OperatorStub.pay_deposit(queue.field, queue)
    %{b | deposit_paid: true, operator_ref: ref}
  end

  defp maybe_pay(%Booking{} = b, :balance, queue) do
    {:ok, ref} = OperatorStub.pay_balance(queue.field, queue)
    %{b | balance_paid: true, operator_ref: ref}
  end

  defp transition(%Booking{} = b, state) do
    b
    |> Booking.changeset(%{
      state: state,
      deposit_paid: b.deposit_paid,
      balance_paid: b.balance_paid,
      operator_ref: b.operator_ref
    })
    |> Repo.update()
  end
end
