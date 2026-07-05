defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  A GenServer that continually fuzzes ClawSpeak and UMP parsers with random binary payloads to catch inconsistent pattern matching or unexpected panics.
  """

  use GenServer
  require Logger

  @interval 1000 # Fuzz every 1 second

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

  defp perform_fuzz do
    # Generate random binary data up to ~1024 bytes using stream_data
    [payload] = StreamData.binary(min_length: 1, max_length: 1024) |> Enum.take(1)

    fuzz_ump(payload)
    fuzz_clawspeak(payload)
  end

  defp fuzz_ump(payload) do
    try do
      GovernanceCore.Protocols.UMP.Parser.parse_frame(payload)
    rescue
      e in [MatchError, FunctionClauseError, RuntimeError, ArgumentError] ->
        Logger.error("UMP Parser Panic during fuzzing: #{inspect(e)} Payload: #{inspect(payload)}")
    end
  end

  defp fuzz_clawspeak(payload) do
    try do
      GovernanceCore.Protocols.ClawSpeak.decode(payload)
    rescue
      e in [MatchError, FunctionClauseError, RuntimeError, ArgumentError] ->
        Logger.error("ClawSpeak Parser Panic during fuzzing: #{inspect(e)} Payload: #{inspect(payload)}")
    end
  end
end
