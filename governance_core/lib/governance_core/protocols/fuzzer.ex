defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  A GenServer that continuously tests the UMP Parser using randomly generated
  binary data to ensure the protocol limits are stressed and exceptions do not crash
  the system (unless intentionally bubbled).
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
    perform_fuzz()
    schedule_fuzz()
    {:noreply, state}
  end

  defp schedule_fuzz do
    Process.send_after(self(), :fuzz, @interval)
  end

  def perform_fuzz do
    Logger.debug("Starting continuous UMP Fuzzing...")

    # Generate random binaries
    payloads = StreamData.binary() |> Enum.take(10)

    Enum.each(payloads, fn payload ->
      try do
        GovernanceCore.Protocols.UMP.Parser.parse_frame(payload)
      rescue
        e in [MatchError, FunctionClauseError, RuntimeError, ArgumentError] ->
          Logger.error("Fuzzer caught exception: #{inspect(e)} on payload: #{inspect(payload)}")
      end
    end)

    Logger.debug("Fuzzing batch complete.")
  end
end
