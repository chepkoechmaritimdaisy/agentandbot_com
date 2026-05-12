defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  A GenServer that continuously fuzzes the ClawSpeak (UMP) protocol parser
  with random binaries to check for inconsistent pattern matching and stability.
  """
  use GenServer
  require Logger

  alias GovernanceCore.Protocols.UMP.Parser

  # Continuous interval: 5 minutes
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

  def perform_fuzzing do
    Logger.info("Starting Continuous ClawSpeak (UMP) Fuzzing...")

    # Use StreamData.binary() to generate random binaries
    # StreamData generators implement Enumerable, so we can use Enum.take directly
    fuzz_data = Enum.take(StreamData.binary(), 100)

    Enum.each(fuzz_data, fn binary ->
      try do
        Parser.parse_frame(binary)
      rescue
        e in MatchError ->
          Logger.error("Fuzzer found MatchError for binary: #{inspect(binary)} - #{inspect(e)}")
        e in FunctionClauseError ->
          Logger.error("Fuzzer found FunctionClauseError for binary: #{inspect(binary)} - #{inspect(e)}")
        e in RuntimeError ->
          Logger.error("Fuzzer found RuntimeError for binary: #{inspect(binary)} - #{inspect(e)}")
        e in ArgumentError ->
          Logger.error("Fuzzer found ArgumentError for binary: #{inspect(binary)} - #{inspect(e)}")
      end
    end)

    Logger.info("ClawSpeak (UMP) Fuzzing completed.")
  end
end
