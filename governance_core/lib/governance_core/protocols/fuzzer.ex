defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Continuously fuzz tests the ClawSpeak UMP Parser.
  """
  use GenServer
  require Logger

  # 5 minutes in milliseconds
  @interval 5 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_fuzz()
    {:ok, state}
  end

  def handle_info(:fuzz, state) do
    perform_fuzzing()
    schedule_fuzz()
    {:noreply, state}
  end

  defp schedule_fuzz do
    Process.send_after(self(), :fuzz, @interval)
  end

  def perform_fuzzing do
    Logger.debug("Starting continuous fuzzing for UMP Parser...")

    # Generate random binaries
    StreamData.binary()
    |> Enum.take(100)
    |> Enum.each(fn payload ->
      try do
        # Call the parser and verify it doesn't crash on garbage
        _result = GovernanceCore.Protocols.UMP.Parser.parse_frame(payload)
      rescue
        e in [MatchError, FunctionClauseError, RuntimeError, ArgumentError] ->
          Logger.error("UMP Parser Fuzzing found a crash! Payload: #{inspect(payload)}, Error: #{inspect(e)}")
      end
    end)

    Logger.debug("UMP Parser Fuzzing cycle completed.")
  end
end
