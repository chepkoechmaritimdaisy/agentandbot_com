defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Continuously fuzzes the ClawSpeak UMP Protocol.
  Generates random binary payloads and passes them to `GovernanceCore.Protocols.UMP.Parser.parse_frame/1`
  to ensure the parser handles malformed inputs without crashing the process.
  """

  use GenServer
  require Logger

  # Continuous interval
  @interval 5 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_fuzzing()
    {:ok, state}
  end

  def handle_info(:fuzz, state) do
    perform_fuzzing()
    schedule_fuzzing()
    {:noreply, state}
  end

  defp schedule_fuzzing do
    Process.send_after(self(), :fuzz, @interval)
  end

  defp perform_fuzzing do
    Logger.info("Starting ClawSpeak UMP Fuzzing...")

    # Generate 100 random binary strings using StreamData
    payloads = Enum.take(StreamData.binary(), 100)

    Enum.each(payloads, fn payload ->
      try do
        # Call parser
        GovernanceCore.Protocols.UMP.Parser.parse_frame(payload)
      rescue
        e in RuntimeError ->
          Logger.error("Fuzzer caught a rescue on payload: #{inspect(payload)}. Error: #{inspect(e)}")
        e in MatchError ->
          Logger.error("Fuzzer caught a MatchError on payload: #{inspect(payload)}. Error: #{inspect(e)}")
        e in FunctionClauseError ->
          Logger.error("Fuzzer caught a FunctionClauseError on payload: #{inspect(payload)}. Error: #{inspect(e)}")
        e ->
          Logger.error("Fuzzer caught an unknown error on payload: #{inspect(payload)}. Error: #{inspect(e)}")
      catch
        kind, value ->
          Logger.error("Fuzzer caught a #{kind} on payload: #{inspect(payload)}. Value: #{inspect(value)}")
      end
    end)

    Logger.info("ClawSpeak UMP Fuzzing completed.")
  end
end
