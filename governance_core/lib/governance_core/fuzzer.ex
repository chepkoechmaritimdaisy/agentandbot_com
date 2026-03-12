defmodule GovernanceCore.Fuzzer do
  @moduledoc """
  Generates random binary payloads periodically to stress test ClawSpeak and UMP protocols.
  """

  use GenServer
  require Logger

  # Random fuzzer interval between 500ms and 2000ms
  @interval 1_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_state) do
    schedule_fuzz()
    {:ok, %{}}
  end

  def handle_info(:fuzz, state) do
    # Generate a random binary using stream_data without running it as a full property test
    # Just grab a sample
    payload = StreamData.binary() |> Enum.take(1) |> hd()

    # 1. Test ClawSpeak
    try do
      GovernanceCore.Protocols.ClawSpeak.decode(payload)
    rescue
      e -> Logger.error("Fuzzer caused a crash in ClawSpeak: #{inspect(e)}")
    end

    # 2. Test UMP Parser
    try do
      GovernanceCore.Protocols.UMP.Parser.parse_frame(payload)
    rescue
      e -> Logger.error("Fuzzer caused a crash in UMP Parser: #{inspect(e)}")
    end

    schedule_fuzz()
    {:noreply, state}
  end

  defp schedule_fuzz do
    # Add some randomness to the interval
    Process.send_after(self(), :fuzz, :rand.uniform(@interval) + 500)
  end
end
