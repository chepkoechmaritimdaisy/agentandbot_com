defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Generates random binary payloads to stress-test the UMP Parser.
  """
  use GenServer
  require Logger

  # Loop every 500ms
  @interval 500

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_fuzz()
    {:ok, state}
  end

  def handle_info(:fuzz, state) do
    fuzz_parser()
    schedule_fuzz()
    {:noreply, state}
  end

  defp schedule_fuzz do
    Process.send_after(self(), :fuzz, @interval)
  end

  defp fuzz_parser do
    [payload] = StreamData.binary() |> Enum.take(1)

    try do
      GovernanceCore.Protocols.UMP.Parser.parse_frame(payload)
    rescue
      e in [MatchError, FunctionClauseError, RuntimeError, ArgumentError] ->
        Logger.error("Fuzzer found a crash in UMP.Parser: #{inspect(e)}")
    end
  end
end
