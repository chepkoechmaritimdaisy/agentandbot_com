defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  A GenServer that continuously fuzzes the UMP Parser using random binary data.
  """
  use GenServer
  require Logger

  alias GovernanceCore.Protocols.UMP.Parser

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
    Logger.debug("Starting continuous UMP fuzzing iteration.")

    StreamData.binary()
    |> Enum.take(100)
    |> Enum.each(fn binary_data ->
      try do
        _result = Parser.parse_frame(binary_data)
      rescue
        e in [MatchError, FunctionClauseError] ->
          Logger.warning("UMP Parser failed on fuzz data: #{inspect(binary_data)}. Error: #{inspect(e)}")
      end
    end)
  end
end
