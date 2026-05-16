defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  A GenServer that fuzzes the UMP Parser continuously to ensure it doesn't crash on invalid input.
  """
  use GenServer
  require Logger

  # 5 minutes in milliseconds
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

  defp perform_fuzzing do
    Logger.info("Starting UMP Fuzzing...")

    try do
      # Generate 100 random binaries to fuzz the parser
      generator = StreamData.binary()

      Enum.take(generator, 100)
      |> Enum.each(fn bin ->
        try do
          GovernanceCore.Protocols.UMP.Parser.parse_frame(bin)
        rescue
          e in [MatchError, FunctionClauseError, RuntimeError, ArgumentError] ->
            Logger.error("Fuzzing crashed the parser! Error: #{inspect(e)}, Input: #{inspect(bin)}")
        end
      end)

      Logger.info("UMP Fuzzing completed successfully.")
    rescue
      e -> Logger.error("Fuzzing task failed: #{inspect(e)}")
    end
  end
end
