defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Periodically generates random UMP payloads and parses them using the UMP Parser
  to detect crashes or inconsistent pattern matching.
  """
  use GenServer
  require Logger

  # 5 minutes
  @interval 5 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_fuzz()
    {:ok, state}
  end

  def handle_info(:fuzz, state) do
    fuzz()
    schedule_fuzz()
    {:noreply, state}
  end

  defp schedule_fuzz do
    Process.send_after(self(), :fuzz, @interval)
  end

  def fuzz do
    Logger.debug("Running UMP Fuzzer")
    payloads = Enum.take(StreamData.binary(), 100)

    Enum.each(payloads, fn payload ->
      try do
        GovernanceCore.Protocols.UMP.Parser.parse_frame(payload)
      rescue
        e in [MatchError, FunctionClauseError, RuntimeError] ->
          Logger.error("UMP Fuzzer detected crash: #{inspect(e)}")
      end
    end)
  end
end
