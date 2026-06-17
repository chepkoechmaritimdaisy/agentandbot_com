defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Generates random binary data to test the ClawSpeak UMP Parser limits continuously.
  """
  use GenServer
  require Logger

  # Runs fuzzing every 5 seconds (fast enough to find bugs, slow enough to not crash the system)
  @interval 5000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_fuzz()
    {:ok, state}
  end

  def handle_info(:fuzz, state) do
    fuzz()
    schedule_fuzz()
    {:noreply, state}
  end

  defp schedule_fuzz do
    Process.send_after(self(), :fuzz, @interval)
  end

  defp fuzz do
    Logger.debug("Running UMP Fuzzing...")

    try do
      # Generate random binary data
      [random_binary] = StreamData.binary() |> Enum.take(1)

      case GovernanceCore.Protocols.UMP.Parser.parse_frame(random_binary) do
        {:ok, _parsed} ->
          # Successfully parsed a valid (or coincidentally valid) frame
          :ok
        {:error, _reason} ->
          # Parser handled it gracefully
          :ok
      end
    rescue
      e in MatchError ->
        Logger.error("UMP Fuzzer: MatchError caught during parsing: #{inspect(e)}")
      e in FunctionClauseError ->
        Logger.error("UMP Fuzzer: FunctionClauseError caught during parsing: #{inspect(e)}")
      e in RuntimeError ->
        Logger.error("UMP Fuzzer: RuntimeError caught during parsing: #{inspect(e)}")
      e in ArgumentError ->
        Logger.error("UMP Fuzzer: ArgumentError caught during parsing: #{inspect(e)}")
    end
  end
end
