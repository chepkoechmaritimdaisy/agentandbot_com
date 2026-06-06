defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Continuously generates random binary payloads to fuzz the UMP Parser
  and verify protocol robustness against malformed data.
  """
  use GenServer
  require Logger

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
    Logger.info("Starting continuous UMP Fuzzing...")

    # Generate 100 random binaries using StreamData
    payloads = StreamData.binary() |> Enum.take(100)

    Enum.each(payloads, fn payload ->
      try do
        GovernanceCore.Protocols.UMP.Parser.parse_frame(payload)
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
    end)

    Logger.info("UMP Fuzzing cycle completed.")
  end
end
