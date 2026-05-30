defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Generates random binary payloads to stress-test the UMP Parser.
  Runs on a continuous interval to constantly ensure the parser gracefully handles garbage input without crashing the node.
  """
  use GenServer
  require Logger
  alias GovernanceCore.Protocols.UMP.Parser

  # Continuous interval (5 minutes)
  @interval 5 * 60 * 1000
  @fuzz_iterations 100

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_fuzz()
    {:ok, state}
  end

  @impl true
  def handle_info(:fuzz, state) do
    perform_fuzzing()
    schedule_fuzz()
    {:noreply, state}
  end

  defp schedule_fuzz do
    Process.send_after(self(), :fuzz, @interval)
  end

  def perform_fuzzing do
    Logger.info("Starting continuous UMP Fuzzing...")

    # Generate random binaries
    payloads = Enum.take(StreamData.binary(), @fuzz_iterations)

    Enum.each(payloads, fn payload ->
      try do
        # Call parser with the fuzzed binary
        _result = Parser.parse_frame(payload)
      rescue
        # Explicitly rescue specific exceptions to prevent over-catching
        e in MatchError ->
          Logger.error("UMP Parser MatchError on payload #{inspect(payload)}: #{inspect(e)}")
        e in FunctionClauseError ->
          Logger.error("UMP Parser FunctionClauseError on payload #{inspect(payload)}: #{inspect(e)}")
        e in RuntimeError ->
          Logger.error("UMP Parser RuntimeError on payload #{inspect(payload)}: #{inspect(e)}")
        e in ArgumentError ->
          Logger.error("UMP Parser ArgumentError on payload #{inspect(payload)}: #{inspect(e)}")
      end
    end)

    Logger.info("UMP Fuzzing complete.")
  end
end
