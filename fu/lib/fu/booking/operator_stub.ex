defmodule Fu.Booking.OperatorStub do
  @moduledoc """
  API stubs + manual coordination for the first 3 partner fields (spec §5).

  No real operator integration yet: each call logs the action a human would
  perform with the field operator and returns a fabricated reference. Booking
  state transitions (spec §2.3) drive these calls; the platform — never the
  player — coordinates the field.
  """
  require Logger

  @doc "Place a speculative hold on `field` for `queue` (spec §2.3 Speculative)."
  def hold(field, queue) do
    Logger.info("[booking-stub] HOLD field=#{field.id} queue=#{queue.id}")
    {:ok, ref()}
  end

  @doc "Pay the deposit once the queue is ≥80% full (spec §2.3 Provisional)."
  def pay_deposit(field, queue) do
    Logger.info("[booking-stub] DEPOSIT field=#{field.id} queue=#{queue.id}")
    {:ok, ref()}
  end

  @doc "Pay the balance once the queue is full & locked (spec §2.3 Confirmed)."
  def pay_balance(field, queue) do
    Logger.info("[booking-stub] BALANCE field=#{field.id} queue=#{queue.id}")
    {:ok, ref()}
  end

  @doc "Release the hold for an empty/failed queue (spec §2.3; deposit forfeit)."
  def release(field, queue) do
    Logger.info("[booking-stub] RELEASE field=#{field.id} queue=#{queue.id}")
    :ok
  end

  defp ref, do: "op-" <> (:crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false))
end
