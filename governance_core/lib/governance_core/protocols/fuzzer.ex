defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Generates random binary payloads to fuzz test the UMP Parser.
  Periodically generates data and passes it to GovernanceCore.Protocols.UMP.Parser.parse_frame/1
  to ensure robust error handling without crashing.
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
    Logger.info("Starting UMP Fuzzer iteration...")

    # Generate random binaries using stream_data
    StreamData.binary()
    |> Enum.take(10)
    |> Enum.each(fn payload ->
      try do
        _ = GovernanceCore.Protocols.UMP.Parser.parse_frame(payload)
      rescue
        e in MatchError ->
          Logger.warning("UMP Parser MatchError during fuzzing: #{inspect(e)}")
        e in FunctionClauseError ->
          Logger.warning("UMP Parser FunctionClauseError during fuzzing: #{inspect(e)}")
        e in RuntimeError ->
          Logger.warning("UMP Parser RuntimeError during fuzzing: #{inspect(e)}")
        e in ArgumentError ->
          Logger.warning("UMP Parser ArgumentError during fuzzing: #{inspect(e)}")
      end
    end)

    Logger.info("UMP Fuzzer iteration completed.")
  end
end
