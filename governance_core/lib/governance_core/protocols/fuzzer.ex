defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  A GenServer that runs continuously (every 5 minutes) to fuzz the UMP Parser
  with random binary payloads using StreamData.
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

  def perform_fuzzing do
    Logger.info("Starting UMP Fuzzing...")

    # Generate 100 random binary payloads using stream_data
    StreamData.binary()
    |> Enum.take(100)
    |> Enum.each(&fuzz_payload/1)

    Logger.info("UMP Fuzzing Completed.")
  end

  defp fuzz_payload(payload) do
    try do
      # Discard output, we only care about crashes/exceptions
      GovernanceCore.Protocols.UMP.Parser.parse_frame(payload)
    rescue
      e in [MatchError, FunctionClauseError, RuntimeError, ArgumentError] ->
        Logger.error("Fuzzer found inconsistent pattern matching or crash! Payload: #{inspect(payload)}, Error: #{inspect(e)}")
    end
  end
end
