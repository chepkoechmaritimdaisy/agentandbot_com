defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Periodically fuzzes the UMP Parser using random binary data to ensure robust pattern matching.
  """
  use GenServer
  require Logger
  alias GovernanceCore.Protocols.UMP.Parser

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

  def perform_fuzz do
    # Generate 100 random binary payloads using stream_data
    payloads = StreamData.binary() |> Enum.take(100)

    Enum.each(payloads, fn payload ->
      try do
        _result = Parser.parse_frame(payload)
      rescue
        e in MatchError ->
          Logger.error("Fuzzer MatchError on payload: #{inspect(payload)} - #{inspect(e)}")
        e in FunctionClauseError ->
          Logger.error("Fuzzer FunctionClauseError on payload: #{inspect(payload)} - #{inspect(e)}")
        e in RuntimeError ->
          Logger.error("Fuzzer RuntimeError on payload: #{inspect(payload)} - #{inspect(e)}")
        e in ArgumentError ->
          Logger.error("Fuzzer ArgumentError on payload: #{inspect(payload)} - #{inspect(e)}")
      end
    end)
  end
end
