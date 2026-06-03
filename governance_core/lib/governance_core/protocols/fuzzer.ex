defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Generates random binary payloads to fuzz the UMP Parser.
  Runs continuously to check for protocol robustness.
  """
  use GenServer
  require Logger

  alias GovernanceCore.Protocols.UMP.Parser

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

  defp perform_fuzz do
    Logger.debug("Starting UMP Parser Fuzzing...")

    # Generate 100 random payloads of varying lengths
    payloads =
      StreamData.binary()
      |> Enum.take(100)

    Enum.each(payloads, fn payload ->
      try do
        _ = Parser.parse_frame(payload)
      rescue
        e in [MatchError, FunctionClauseError, RuntimeError, ArgumentError] ->
          Logger.error("Fuzzing crashed parser with payload: #{inspect(payload)}, error: #{inspect(e)}")
      end
    end)

    Logger.debug("UMP Parser Fuzzing complete.")
  end
end
