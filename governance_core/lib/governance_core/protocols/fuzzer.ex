defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Continuously fuzzes the ClawSpeak decoder with random binary inputs to identify and log inconsistent pattern matching or parsing errors.
  """
  use GenServer
  require Logger

  @interval 1_000 # Fuzz every second
  @batch_size 10

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_fuzz()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:fuzz, state) do
    fuzz()
    schedule_fuzz()
    {:noreply, state}
  end

  defp schedule_fuzz do
    Process.send_after(self(), :fuzz, @interval)
  end

  defp fuzz do
    StreamData.binary()
    |> Enum.take(@batch_size)
    |> Enum.each(fn binary_data ->
      try do
        GovernanceCore.Protocols.ClawSpeak.decode(binary_data)
      rescue
        e in MatchError ->
          Logger.error("ClawSpeak Fuzzer MatchError: #{inspect(e)}")

        e in FunctionClauseError ->
          Logger.error("ClawSpeak Fuzzer FunctionClauseError: #{inspect(e)}")

        e in RuntimeError ->
          Logger.error("ClawSpeak Fuzzer RuntimeError: #{inspect(e)}")

        e in ArgumentError ->
          Logger.error("ClawSpeak Fuzzer ArgumentError: #{inspect(e)}")
      end
    end)
  end
end
