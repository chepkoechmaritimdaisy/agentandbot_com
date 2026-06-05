defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  A background Fuzzer that continuously generates random binary data using
  StreamData to test the GovernanceCore.Protocols.UMP.Parser module,
  ensuring it doesn't crash on malformed inputs.
  """
  use GenServer
  require Logger

  # 5 minutes in milliseconds
  @interval 5 * 60 * 1000

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

  defp perform_fuzzing do
    # Generate 1 random binary payload using StreamData
    [payload] = StreamData.binary() |> Enum.take(1)

    try do
      _result = GovernanceCore.Protocols.UMP.Parser.parse_frame(payload)
      # We don't care about the result, only that it doesn't crash
    rescue
      e in [MatchError, FunctionClauseError, RuntimeError, ArgumentError] ->
        Logger.error("Fuzzer found a crash in UMP.Parser! Payload: #{inspect(payload)}, Error: #{inspect(e)}")
    end
  end
end
