defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  GenServer that fuzzes the UMP Parser continuously.
  """
  use GenServer
  require Logger

  # Continuous execution every 5 minutes
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
    Logger.info("Starting UMP Parser Fuzzing...")

    # Generate 100 random binary inputs
    Enum.each(1..100, fn _ ->
      size = :rand.uniform(10) - 1
      payload = :crypto.strong_rand_bytes(size)

      try do
        GovernanceCore.Protocols.UMP.Parser.parse_frame(payload)
      rescue
        e in [MatchError, FunctionClauseError, RuntimeError, ArgumentError] ->
          Logger.error("Fuzzer found a crash! Payload: #{inspect(payload)}, Error: #{inspect(e)}")
      catch
        kind, value ->
          Logger.error("Fuzzer caught #{kind}! Payload: #{inspect(payload)}, Value: #{inspect(value)}")
      end
    end)

    Logger.info("Finished UMP Parser Fuzzing.")
  end
end
