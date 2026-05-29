defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Generates random binary data to test the UMP Parser for inconsistent pattern matching
  and crashes. Continuously fuzzes the parser in the background.
  """
  use GenServer
  require Logger

  # 5 minutes in milliseconds
  @interval 5 * 60 * 1000
  @num_fuzzes 100

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

  def perform_fuzz do
    Logger.info("Starting continuous UMP fuzzing...")

    # Generate random binaries
    StreamData.binary()
    |> Enum.take(@num_fuzzes)
    |> Enum.each(fn bin ->
      try do
        GovernanceCore.Protocols.UMP.Parser.parse_frame(bin)
      rescue
        e in [MatchError, FunctionClauseError, RuntimeError, ArgumentError] ->
          Logger.error("Fuzzing crashed parser! Payload: #{inspect(bin)}, Error: #{inspect(e)}")
      end
    end)
  end
end
