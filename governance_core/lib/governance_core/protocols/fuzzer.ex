defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Generates random binary data to test the limits of the ClawSpeak/UMP protocol parser.
  """
  use GenServer
  require Logger

  # Continuous interval (5 minutes)
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
    Logger.info("Starting UMP Protocol Fuzzing...")

    # Generate 10 random binaries using StreamData
    binaries = Enum.take(StreamData.binary(), 10)

    Enum.each(binaries, fn binary ->
      try do
        # We don't care about the return value, just that it doesn't crash the VM
        GovernanceCore.Protocols.UMP.Parser.parse_frame(binary)
      rescue
        e in [MatchError, FunctionClauseError, RuntimeError, ArgumentError] ->
          Logger.warning("Fuzzer caught exception during parsing: #{inspect(e)}")
      end
    end)

    Logger.info("UMP Protocol Fuzzing completed.")
  end
end
