defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Runs continuous property-based fuzzing tests on the ClawSpeak and UMP parsers.
  Generates random binary data using `StreamData.binary()` to stress test the parsers,
  ensuring they don't crash on inconsistent patterns or invalid frames.
  """
  use GenServer
  require Logger

  @interval 60 * 1000 # 1 minute for continuous fuzzing cycles

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    Logger.info("Starting Continuous Fuzzer for Protocols...")
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

  defp perform_fuzz do
    # Generate 100 random binary samples using StreamData
    samples = Enum.take(StreamData.binary(), 100)

    Enum.each(samples, fn data ->
      fuzz_clawspeak(data)
      fuzz_ump(data)
    end)
  end

  defp fuzz_clawspeak(data) do
    try do
      _result = GovernanceCore.Protocols.ClawSpeak.decode(data)
      # We just want to ensure it doesn't crash.
    rescue
      e ->
        Logger.error("ClawSpeak Parser crashed during fuzzing: #{inspect(e)} with data: #{inspect(data)}")
    catch
      kind, value ->
        Logger.error("ClawSpeak Parser caught #{kind} during fuzzing: #{inspect(value)} with data: #{inspect(data)}")
    end
  end

  defp fuzz_ump(data) do
    try do
      _result = GovernanceCore.Protocols.UMP.Parser.parse_frame(data)
      # We just want to ensure it doesn't crash.
    rescue
      e ->
        Logger.error("UMP Parser crashed during fuzzing: #{inspect(e)} with data: #{inspect(data)}")
    catch
      kind, value ->
        Logger.error("UMP Parser caught #{kind} during fuzzing: #{inspect(value)} with data: #{inspect(data)}")
    end
  end
end
