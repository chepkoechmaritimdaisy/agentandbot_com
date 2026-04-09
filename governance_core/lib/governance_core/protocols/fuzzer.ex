defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  A GenServer that continuously fuzzes and stress-tests the ClawSpeak and UMP parsers.
  It generates random binary data using StreamData and ensures the parsers do not crash
  the process on invalid inputs.
  """
  use GenServer
  require Logger

  @interval 1000 # 1 second interval between fuzzing batches

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    Logger.info("Starting Protocol Fuzzer...")
    schedule_fuzzing()
    {:ok, state}
  end

  def handle_info(:fuzz, state) do
    fuzz_parsers()
    schedule_fuzzing()
    {:noreply, state}
  end

  defp schedule_fuzzing do
    Process.send_after(self(), :fuzz, @interval)
  end

  defp fuzz_parsers do
    # Generate random binary inputs
    # StreamData.binary() creates random binaries. We'll take a batch.
    generator = StreamData.binary()
    inputs = Enum.take(generator, 100) # take 100 random binary samples per cycle

    Enum.each(inputs, fn input ->
      # Fuzz ClawSpeak Parser
      try do
        GovernanceCore.Protocols.ClawSpeak.decode(input)
      rescue
        e -> Logger.warning("ClawSpeak Parser raised exception: #{inspect(e)}")
      catch
        kind, value -> Logger.warning("ClawSpeak Parser threw: #{kind} #{inspect(value)}")
      end

      # Fuzz UMP Parser
      try do
        GovernanceCore.Protocols.UMP.parse(input)
      rescue
        e -> Logger.warning("UMP Parser raised exception: #{inspect(e)}")
      catch
        kind, value -> Logger.warning("UMP Parser threw: #{kind} #{inspect(value)}")
      end
    end)
  end
end
