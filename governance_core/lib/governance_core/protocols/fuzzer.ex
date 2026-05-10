defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  A GenServer that periodically fuzzes the ClawSpeak (UMP) protocol parser
  to ensure robust error handling without crashing.
  """
  use GenServer
  require Logger

  alias GovernanceCore.Protocols.UMP.Parser

  @interval 5 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_fuzz()
    {:ok, state}
  end

  def handle_info(:fuzz, state) do
    fuzz_parser()
    schedule_fuzz()
    {:noreply, state}
  end

  defp schedule_fuzz do
    Process.send_after(self(), :fuzz, @interval)
  end

  defp fuzz_parser do
    Logger.debug("Starting ClawSpeak UMP fuzzing cycle")

    # Generate random binary data using StreamData
    [random_data] = Enum.take(StreamData.binary(), 1)

    try do
      _result = Parser.parse_frame(random_data)
      Logger.debug("Fuzzing cycle completed: Parser handled random data gracefully")
    rescue
      e in MatchError ->
        Logger.error("Fuzzer caught MatchError: #{inspect(e)}")

      e in FunctionClauseError ->
        Logger.error("Fuzzer caught FunctionClauseError: #{inspect(e)}")

      e in RuntimeError ->
        Logger.error("Fuzzer caught RuntimeError: #{inspect(e)}")

      e in ArgumentError ->
        Logger.error("Fuzzer caught ArgumentError: #{inspect(e)}")
    end
  end
end
