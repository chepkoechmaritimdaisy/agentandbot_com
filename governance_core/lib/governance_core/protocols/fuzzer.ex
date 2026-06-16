defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  A GenServer that periodically fuzz tests the UMP parser using stream_data.
  """
  use GenServer
  require Logger

  @interval 60 * 1000 # 1 minute

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
    # Generate 100 random binary payloads using StreamData
    payloads = StreamData.binary() |> Enum.take(100)

    Enum.each(payloads, fn payload ->
      try do
        GovernanceCore.Protocols.UMP.parse(payload)
      rescue
        e in [MatchError, FunctionClauseError, RuntimeError, ArgumentError] ->
          Logger.error("UMP Parser crashed on fuzzed payload! Payload: #{inspect(payload)}, Error: #{inspect(e)}")
      end
    end)
  end
end
