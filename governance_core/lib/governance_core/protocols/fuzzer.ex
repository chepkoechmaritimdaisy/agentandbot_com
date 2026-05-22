defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Fuzzer GenServer for ClawSpeak UMP protocol.
  Continuously fuzzes the UMP Parser to detect inconsistent pattern matching.
  """
  use GenServer
  require Logger

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
    Logger.info("Starting UMP Fuzzing...")

    StreamData.binary()
    |> Enum.take(100)
    |> Enum.each(fn payload ->
      try do
        GovernanceCore.Protocols.UMP.Parser.parse_frame(payload)
      rescue
        e in [MatchError, FunctionClauseError, RuntimeError, ArgumentError] ->
          Logger.error("UMP Parser crashed on payload: #{inspect(payload)} - Error: #{inspect(e)}")
      end
    end)
  end
end
