defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Continuously fuzzes the ClawSpeak parser with randomly generated binary payloads
  to ensure robust error handling without crashing.
  """
  use GenServer
  require Logger
  alias GovernanceCore.Protocols.ClawSpeak

  @interval 1000

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
    # Generate 1 random binary payload
    payload = StreamData.binary() |> Enum.take(1) |> hd()

    try do
      _result = ClawSpeak.decode(payload)
      # We don't care about the result, just that it didn't crash
    rescue
      e in MatchError ->
        Logger.error("Fuzzer caught MatchError: #{inspect(e)}")
      e in FunctionClauseError ->
        Logger.error("Fuzzer caught FunctionClauseError: #{inspect(e)}")
      e in RuntimeError ->
        Logger.error("Fuzzer caught RuntimeError: #{inspect(e)}")
      e in ArgumentError ->
        Logger.error("Fuzzer caught ArgumentError: #{inspect(e)}")
    end
  end
end
