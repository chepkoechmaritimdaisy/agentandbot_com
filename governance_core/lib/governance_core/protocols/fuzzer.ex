defmodule GovernanceCore.Protocols.Fuzzer do
  use GenServer
  require Logger

  @interval 5 * 60 * 1000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_fuzz()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:fuzz, state) do
    Logger.info("Running continuous UMP Fuzzing...")

    # Generate 100 random binary frames
    payloads = Enum.take(StreamData.binary(), 100)

    Enum.each(payloads, fn payload ->
      try do
        _result = GovernanceCore.Protocols.UMP.Parser.parse_frame(payload)
      rescue
        e in [MatchError, FunctionClauseError, RuntimeError, ArgumentError] ->
          Logger.error("UMP Parser crashed on payload #{inspect(payload)}: #{inspect(e)}")
      end
    end)

    schedule_fuzz()
    {:noreply, state}
  end

  defp schedule_fuzz do
    Process.send_after(self(), :fuzz, @interval)
  end
end
