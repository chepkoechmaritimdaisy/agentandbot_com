defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Generates random binary frames to test the Ultra Mini Agent Protocol (UMP) Parser.
  Runs continuously to stress-test the protocol boundaries.
  """
  use GenServer
  require Logger

  # 5 minutes interval for continuous processing
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
    perform_fuzz()
    schedule_fuzz()
    {:noreply, state}
  end

  defp schedule_fuzz do
    Process.send_after(self(), :fuzz, @interval)
  end

  def perform_fuzz do
    Logger.debug("Starting continuous ClawSpeak (UMP) Fuzzing...")

    # Generate 10 random binary sequences
    binaries = Enum.take(StreamData.binary(), 10)

    Enum.each(binaries, fn bin ->
      try do
        # Pass random binary data to parser
        GovernanceCore.Protocols.UMP.Parser.parse_frame(bin)
      rescue
        e in [MatchError, FunctionClauseError, RuntimeError] ->
          Logger.warning("Fuzzer caught expected error during parsing: #{inspect(e)}")
      end
    end)
  end
end
