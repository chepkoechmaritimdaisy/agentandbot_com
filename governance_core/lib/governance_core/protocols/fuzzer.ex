defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  A GenServer that continuously fuzzes the ClawSpeak and UMP protocols.
  It generates random binary data to test the limits of the protocol parsers.
  """
  use GenServer
  require Logger

  # 1 minute in milliseconds
  @interval 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_fuzzing()
    {:ok, state}
  end

  def handle_info(:fuzz, state) do
    fuzz_clawspeak()
    fuzz_ump()
    schedule_fuzzing()
    {:noreply, state}
  end

  defp schedule_fuzzing do
    Process.send_after(self(), :fuzz, @interval)
  end

  defp fuzz_clawspeak do
    Logger.debug("Fuzzing ClawSpeak protocol...")

    # Generate random binary data using stream_data and test the parser
    # We use StreamData.binary() and test decode/1
    # We catch any potential crashes to ensure the GenServer doesn't die.

    # StreamData implements Enumerable natively in recent versions,
    # so we can take samples directly.
    samples = Enum.take(StreamData.binary(), 100)

    Enum.each(samples, fn binary_data ->
      try do
        _result = GovernanceCore.Protocols.ClawSpeak.decode(binary_data)
      rescue
        e -> Logger.error("ClawSpeak parser crashed during fuzzing: #{inspect(e)}")
      catch
        kind, value ->
          Logger.error("ClawSpeak parser threw #{kind}: #{inspect(value)}")
      end
    end)
  end

  defp fuzz_ump do
    Logger.debug("Fuzzing UMP protocol...")

    # Generate random binary data and test the UMP frame parser
    samples = Enum.take(StreamData.binary(), 100)

    Enum.each(samples, fn binary_data ->
      try do
        _result = GovernanceCore.Protocols.UMP.Parser.parse_frame(binary_data)
      rescue
        e -> Logger.error("UMP parser crashed during fuzzing: #{inspect(e)}")
      catch
        kind, value ->
          Logger.error("UMP parser threw #{kind}: #{inspect(value)}")
      end
    end)
  end
end
