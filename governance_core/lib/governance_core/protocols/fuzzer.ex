defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Generates random binary frames to test the limits of the ClawSpeak/UMP protocol.
  Ensures the parser can handle malformed or unexpected input without crashing the system.
  """

  use GenServer
  require Logger

  # Continuous interval (5 minutes)
  @interval 5 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_fuzz()
    {:ok, state}
  end

  def handle_info(:fuzz, state) do
    perform_fuzz()
    schedule_fuzz()
    {:noreply, state}
  end

  defp schedule_fuzz do
    Process.send_after(self(), :fuzz, @interval)
  end

  defp perform_fuzz do
    Logger.info("Starting continuous ClawSpeak/UMP Fuzzing...")

    # Generate 100 random binary strings using StreamData
    Enum.take(StreamData.binary(), 100)
    |> Enum.each(&process_frame/1)

    Logger.info("Fuzzing batch complete.")
  end

  defp process_frame(frame) do
    try do
      GovernanceCore.Protocols.UMP.Parser.parse_frame(frame)
    rescue
      e in [MatchError, FunctionClauseError, RuntimeError] ->
        Logger.error("Fuzzer found parsing error: #{inspect(e)} for frame: #{inspect(frame)}")
    end
  end
end
