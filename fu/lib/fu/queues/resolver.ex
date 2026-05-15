defmodule Fu.Queues.Resolver do
  @moduledoc """
  Periodic worker that runs T-3h partial-fill resolution (spec §2.4, S35).
  Every tick it finds queues whose lock window has arrived and confirms,
  extends (once), or cancels them.
  """
  use GenServer
  require Logger

  @interval :timer.minutes(1)

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    schedule()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:tick, state) do
    for queue <- Fu.Queues.due_for_resolution() do
      {outcome, _} = Fu.Queues.resolve_partial_fill(queue)
      Logger.info("[resolver] queue #{queue.id} → #{outcome}")
    end

    schedule()
    {:noreply, state}
  end

  defp schedule, do: Process.send_after(self(), :tick, @interval)
end
