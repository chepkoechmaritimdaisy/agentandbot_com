defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  A GenServer that continuously stress-tests the UMP Parser using randomized
  binary data to ensure protocol robustness and catch edge-case crashes.
  """
  use GenServer
  require Logger

  # Fuzz interval (e.g. 5 seconds)
  @fuzz_interval 5_000

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
    Process.send_after(self(), :fuzz, @fuzz_interval)
  end

  defp perform_fuzzing do
    # Generate random binary data using stream_data generator
    [payload] = StreamData.binary() |> Enum.take(1)

    try do
      GovernanceCore.Protocols.UMP.Parser.parse_frame(payload)
      # We don't care about the return value (whether it parses or fails cleanly).
      # We only care that it doesn't crash the process.
    rescue
      e in MatchError ->
        Logger.error("Fuzzer caught MatchError: #{inspect(e)} on payload: #{inspect(payload)}")
      e in FunctionClauseError ->
        Logger.error("Fuzzer caught FunctionClauseError: #{inspect(e)} on payload: #{inspect(payload)}")
      e in RuntimeError ->
        Logger.error("Fuzzer caught RuntimeError: #{inspect(e)} on payload: #{inspect(payload)}")
      e in ArgumentError ->
        Logger.error("Fuzzer caught ArgumentError: #{inspect(e)} on payload: #{inspect(payload)}")
    end
  end
end
