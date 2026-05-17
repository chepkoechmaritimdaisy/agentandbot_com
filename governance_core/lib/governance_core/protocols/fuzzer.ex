defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  A GenServer that continuously fuzzes the UMP Parser with random binaries
  to ensure protocol boundaries aren't breaking (e.g. via inconsistent pattern matching).
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
    Logger.info("Running UMP Fuzzer iteration...")

    # Generate random binaries using StreamData
    StreamData.binary()
    |> Enum.take(100)
    |> Enum.each(fn bin ->
      try do
        GovernanceCore.Protocols.UMP.Parser.parse_frame(bin)
      rescue
        e in [MatchError, FunctionClauseError, RuntimeError, ArgumentError] ->
          Logger.error("Fuzzer found an issue with binary #{inspect(bin)}: #{Exception.message(e)}")
      end
    end)

    schedule_fuzz()
    {:noreply, state}
  end

  defp schedule_fuzz do
    Process.send_after(self(), :fuzz, @interval)
  end
end
