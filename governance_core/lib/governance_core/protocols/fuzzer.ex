defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Continuously fuzzes the UMP Parser to detect inconsistent pattern matching.
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
    Logger.info("Starting Continuous UMP Fuzzing...")

    # Generate 100 random binary frames
    Enum.each(1..100, fn _ ->
      payload = StreamData.binary() |> Enum.take(1) |> hd()

      try do
        GovernanceCore.Protocols.UMP.Parser.parse_frame(payload)
      rescue
        e in MatchError -> Logger.error("UMP Parser MatchError on payload: #{inspect(payload)} - #{inspect(e)}")
        e in FunctionClauseError -> Logger.error("UMP Parser FunctionClauseError on payload: #{inspect(payload)} - #{inspect(e)}")
        e in RuntimeError -> Logger.error("UMP Parser RuntimeError on payload: #{inspect(payload)} - #{inspect(e)}")
        e in ArgumentError -> Logger.error("UMP Parser ArgumentError on payload: #{inspect(payload)} - #{inspect(e)}")
      end
    end)
  end
end
