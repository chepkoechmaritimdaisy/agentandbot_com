defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Generates random binary payloads to continuously fuzz and stress-test the ClawSpeak UMP Parser.
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
    fuzz_parser()
    schedule_fuzz()
    {:noreply, state}
  end

  defp schedule_fuzz do
    Process.send_after(self(), :fuzz, @interval)
  end

  defp fuzz_parser do
    # Generate random binary data to test edge cases
    payload = :crypto.strong_rand_bytes(10)

    try do
      _result = GovernanceCore.Protocols.UMP.Parser.parse_frame(payload)
      # We don't care about the result, just that it doesn't crash the process
    rescue
      e in MatchError ->
        Logger.warning("Fuzzer caught MatchError: #{inspect(e)} on payload #{inspect(payload)}")

      e in FunctionClauseError ->
        Logger.warning("Fuzzer caught FunctionClauseError: #{inspect(e)} on payload #{inspect(payload)}")

      e in RuntimeError ->
        Logger.warning("Fuzzer caught RuntimeError: #{inspect(e)} on payload #{inspect(payload)}")

      e in ArgumentError ->
        Logger.warning("Fuzzer caught ArgumentError: #{inspect(e)} on payload #{inspect(payload)}")
    end
  end
end
