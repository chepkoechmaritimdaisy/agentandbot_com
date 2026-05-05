defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Continuously fuzzes the UMP Protocol parser with random binary data
  to ensure robust pattern matching and error handling.
  """
  use GenServer
  require Logger
  alias GovernanceCore.Protocols.UMP.Parser

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

  def perform_fuzzing do
    Logger.debug("Starting continuous UMP fuzzing...")

    StreamData.binary()
    |> Enum.take(100)
    |> Enum.each(fn binary_data ->
      try do
        # We don't care about the result, just that it doesn't crash the GenServer
        _ = Parser.parse_frame(binary_data)
      rescue
        e in [MatchError, FunctionClauseError, RuntimeError, ArgumentError] ->
          Logger.error("UMP Fuzzer detected a crash! Input: #{inspect(binary_data)}, Error: #{inspect(e)}")
      end
    end)

    Logger.debug("UMP Fuzzing cycle complete.")
  end
end
