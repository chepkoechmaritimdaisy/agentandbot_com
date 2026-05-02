defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Periodically generates random binary data and passes it to the UMP Parser
  to ensure robust error handling without crashing on malformed payloads.
  """

  use GenServer
  require Logger

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
    fuzz_parser()
    schedule_fuzz()
    {:noreply, state}
  end

  defp schedule_fuzz do
    Process.send_after(self(), :fuzz, @interval)
  end

  def fuzz_parser do
    Logger.debug("Starting Fuzzer run...")

    # Generate 10 random binaries using stream_data natively via Enumerable protocol
    binaries = Enum.take(StreamData.binary(), 10)

    Enum.each(binaries, fn binary ->
      try do
        GovernanceCore.Protocols.UMP.Parser.parse_frame(binary)
      rescue
        e in [MatchError, FunctionClauseError, RuntimeError, ArgumentError] ->
          Logger.error("Fuzzer caught exception from parser: #{inspect(e)}")
      end
    end)
  end
end
