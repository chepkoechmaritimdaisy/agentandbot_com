defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Continuously fuzzes the UMP Parser using stream_data generators.
  """
  use GenServer
  require Logger

  # 10 seconds interval for fuzzing
  @interval 10_000

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
    perform_fuzz()
    schedule_fuzz()
    {:noreply, state}
  end

  defp schedule_fuzz do
    Process.send_after(self(), :fuzz, @interval)
  end

  defp perform_fuzz do
    Logger.debug("Starting Fuzzing of UMP Parser...")

    # Generate 100 random binary strings using stream_data
    StreamData.binary()
    |> Enum.take(100)
    |> Enum.each(&fuzz_payload/1)
  end

  defp fuzz_payload(payload) do
    try do
      _ = GovernanceCore.Protocols.UMP.parse(payload)
    rescue
      e in [MatchError, FunctionClauseError, RuntimeError, ArgumentError] ->
        Logger.error("Fuzzer found a crash in UMP.parse/1 with payload #{inspect(payload)}: #{inspect(e)}")
    end
  end
end
