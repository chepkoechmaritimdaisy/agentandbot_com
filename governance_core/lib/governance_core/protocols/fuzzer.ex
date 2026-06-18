defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Continuously fuzzes the ClawSpeak binary protocol decoder to discover inconsistencies
  or crashes by generating random binary streams.
  """
  use GenServer
  require Logger

  # 1-second interval for fuzzing iteration
  @interval 1000

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
    StreamData.binary()
    |> Enum.take(10)
    |> Enum.each(fn payload ->
      try do
        _result = GovernanceCore.Protocols.ClawSpeak.decode(payload)
      rescue
        e in [MatchError, FunctionClauseError, RuntimeError, ArgumentError] ->
          Logger.error("ClawSpeak decoder crash during fuzzing: #{inspect(e)}")
      end
    end)
  end
end
