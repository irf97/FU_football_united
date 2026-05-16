defmodule Fu.Ranking.DecayWorker do
  @moduledoc """
  Periodic worker that applies rank decay (spec §2.9). Every 24h it drifts
  idle players' ranks toward 50 via `Fu.Ranking.apply_decay/0` and logs how
  many players were decayed. Suspended players are exempt (spec §2.9).
  """
  use GenServer
  require Logger

  @interval :timer.hours(24)

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    schedule()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:tick, state) do
    count = Fu.Ranking.apply_decay()
    Logger.info("[decay] #{count} players decayed")

    schedule()
    {:noreply, state}
  end

  defp schedule, do: Process.send_after(self(), :tick, @interval)
end
