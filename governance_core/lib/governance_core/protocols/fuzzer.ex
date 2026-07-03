defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Periodically generates random binary data and feeds it into the UMP parser
  to stress test and ensure it doesn't crash or behave unexpectedly.
  """
  use GenServer
  require Logger

  @interval 5_000 # Fuzz every 5 seconds

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
    # Generate 1 random binary payload
    payload = StreamData.binary() |> Enum.take(1) |> hd()

    try do
      GovernanceCore.Protocols.UMP.parse(payload)
      # We don't care about the result, only that it doesn't crash unexpectedly.
    rescue
      e in [MatchError, FunctionClauseError, RuntimeError, ArgumentError] ->
        Logger.error("UMP Parser Fuzzing Crash Detected! Error: #{inspect(e)}")
        Logger.error("Failing Payload: #{inspect(payload)}")
    end
  end
end
