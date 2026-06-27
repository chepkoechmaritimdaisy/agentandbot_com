defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  A GenServer that continuously fuzzes ClawSpeak and UMP protocols with random binary payloads.
  """
  use GenServer
  require Logger
  alias GovernanceCore.Protocols.{UMP, ClawSpeak}

  @interval 1000 # 1 second

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(state) do
    schedule_fuzz()
    {:ok, state}
  end

  def handle_info(:fuzz, state) do
    fuzz_ump()
    fuzz_clawspeak()
    schedule_fuzz()
    {:noreply, state}
  end

  defp schedule_fuzz do
    Process.send_after(self(), :fuzz, @interval)
  end

  defp fuzz_ump do
    # Generate random binary using stream_data
    payload = StreamData.binary() |> Enum.take(1) |> hd()

    try do
      UMP.parse(payload)
    rescue
      e in [MatchError, FunctionClauseError, RuntimeError, ArgumentError] ->
        Logger.error("UMP Parser broken by fuzzer! Payload: #{inspect(payload)}, Error: #{inspect(e)}")
    end
  end

  defp fuzz_clawspeak do
    # Generate random binary using stream_data
    payload = StreamData.binary() |> Enum.take(1) |> hd()

    try do
      ClawSpeak.decode(payload)
    rescue
      e in [MatchError, FunctionClauseError, RuntimeError, ArgumentError] ->
        Logger.error("ClawSpeak Decoder broken by fuzzer! Payload: #{inspect(payload)}, Error: #{inspect(e)}")
    end
  end
end
