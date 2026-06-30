defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Generates random binary data using `stream_data` to continuously fuzz the UMP Parser
  and test protocol robustness against inconsistent pattern matching.
  """
  use GenServer
  require Logger

  # Default interval of 500ms
  @interval 500

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
    perform_fuzzing()
    schedule_fuzz()
    {:noreply, state}
  end

  defp schedule_fuzz do
    Process.send_after(self(), :fuzz, @interval)
  end

  def perform_fuzzing do
    # Generate 1 to 5 random binary chunks and test the parser
    StreamData.binary()
    |> Enum.take(:rand.uniform(5))
    |> Enum.each(fn payload ->
      try do
        GovernanceCore.Protocols.UMP.Parser.parse_frame(payload)
      rescue
        e in [MatchError, FunctionClauseError, RuntimeError, ArgumentError] ->
          Logger.error("UMP Parser Fuzzing failed on payload #{inspect(payload)}: #{inspect(e)}")
      end
    end)
  end
end
