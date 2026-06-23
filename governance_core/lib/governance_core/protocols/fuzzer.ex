defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Generates random binary payloads using StreamData and fuzzes the UMP Parser
  continuously to check for inconsistent pattern matching and unhandled crashes.
  """
  use GenServer
  require Logger

  @interval 500

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_fuzz()
    {:ok, state}
  end

  def handle_info(:fuzz, state) do
    fuzz_ump_parser()
    schedule_fuzz()
    {:noreply, state}
  end

  defp schedule_fuzz do
    Process.send_after(self(), :fuzz, @interval)
  end

  defp fuzz_ump_parser do
    # Generate random binary data
    payloads = StreamData.binary() |> Enum.take(10)

    Enum.each(payloads, fn payload ->
      try do
        # We don't care about the result, only that it doesn't crash ungracefully
        _ = GovernanceCore.Protocols.UMP.Parser.parse_frame(payload)
      rescue
        e in [MatchError, FunctionClauseError, RuntimeError, ArgumentError] ->
          Logger.error("UMP Parser Fuzzing Crash! Payload: #{inspect(payload)}, Error: #{inspect(e)}")
      end
    end)
  end
end
