defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Generates random binary data to test the limits of the ClawSpeak (UMP) protocol parser.
  It continually verifies that the protocol parser does not crash on malformed inputs.
  """
  use GenServer
  require Logger

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

  def perform_fuzz do
    Logger.debug("Starting UMP Protocol Fuzzing...")
    random_bytes = :crypto.strong_rand_bytes(10)

    try do
      GovernanceCore.Protocols.UMP.Parser.parse_frame(random_bytes)
    rescue
      e in [MatchError, FunctionClauseError, RuntimeError, ArgumentError] ->
        Logger.error("UMP Parser crashed during fuzzing! Exception: #{inspect(e)}")
    end
  end
end
