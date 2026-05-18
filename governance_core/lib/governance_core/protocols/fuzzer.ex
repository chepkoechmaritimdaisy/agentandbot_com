defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  A GenServer that continuously fuzzes the UMP Parser using StreamData.
  """
  use GenServer
  require Logger

  # 5 minutes in milliseconds
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
    Logger.info("Starting UMP Parser fuzzing...")

    # Generate 100 random binary payloads using StreamData
    payloads = StreamData.binary() |> Enum.take(100)

    Enum.each(payloads, fn payload ->
      try do
        GovernanceCore.Protocols.UMP.Parser.parse_frame(payload)
      rescue
        e in [MatchError, FunctionClauseError, RuntimeError, ArgumentError] ->
          Logger.error("Fuzzing failed for payload: #{inspect(payload)} with error: #{inspect(e)}")
      end
    end)

    Logger.info("UMP Parser fuzzing completed.")
  end
end
