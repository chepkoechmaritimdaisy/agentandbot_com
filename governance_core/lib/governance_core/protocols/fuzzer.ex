defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Generates random binary payloads to test the UMP Parser.
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
    perform_fuzzing()
    schedule_fuzz()
    {:noreply, state}
  end

  defp schedule_fuzz do
    Process.send_after(self(), :fuzz, @interval)
  end

  def perform_fuzzing do
    Logger.info("Starting UMP Fuzzing...")

    try do
      # Generate 100 random binary payloads using StreamData
      payloads = StreamData.binary() |> Enum.take(100)

      Enum.each(payloads, fn payload ->
        try do
          GovernanceCore.Protocols.UMP.Parser.parse_frame(payload)
        rescue
          e in [MatchError, FunctionClauseError, RuntimeError, ArgumentError] ->
            Logger.error("UMP Parser crashed on fuzzed payload: #{inspect(payload)} with error: #{inspect(e)}")
        end
      end)

      Logger.info("UMP Fuzzing completed.")
    rescue
      e -> Logger.error("Unexpected error during UMP fuzzing: #{inspect(e)}")
    end
  end
end
