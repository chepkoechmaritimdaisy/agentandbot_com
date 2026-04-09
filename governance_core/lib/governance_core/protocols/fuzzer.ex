defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Periodically fuzzes ClawSpeak and UMP protocols to ensure they don't crash
  the parsing processes when handling malformed binary data.
  """
  use GenServer
  require Logger

  @interval 60 * 1000 # 1 minute interval

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_fuzzing()
    {:ok, state}
  end

  def handle_info(:fuzz, state) do
    perform_fuzzing()
    schedule_fuzzing()
    {:noreply, state}
  end

  defp schedule_fuzzing do
    Process.send_after(self(), :fuzz, @interval)
  end

  defp perform_fuzzing do
    Logger.debug("Starting ClawSpeak and UMP fuzzing iteration...")

    # stream_data generators are Enumerable
    binary_generator = StreamData.binary()

    # Generate 100 random binary strings
    fuzz_inputs = Enum.take(binary_generator, 100)

    Enum.each(fuzz_inputs, fn input ->
      fuzz_ump(input)
      fuzz_clawspeak(input)
    end)

    Logger.debug("Fuzzing iteration complete.")
  end

  defp fuzz_ump(input) do
    try do
      _ = GovernanceCore.Protocols.UMP.Parser.parse_frame(input)
    rescue
      e -> Logger.warning("UMP fuzzer caught exception: #{inspect(e)}")
    catch
      :exit, reason -> Logger.warning("UMP fuzzer caught exit: #{inspect(reason)}")
      :throw, reason -> Logger.warning("UMP fuzzer caught throw: #{inspect(reason)}")
    end
  end

  defp fuzz_clawspeak(input) do
    try do
      _ = GovernanceCore.Protocols.ClawSpeak.decode(input)
    rescue
      e -> Logger.warning("ClawSpeak fuzzer caught exception: #{inspect(e)}")
    catch
      :exit, reason -> Logger.warning("ClawSpeak fuzzer caught exit: #{inspect(reason)}")
      :throw, reason -> Logger.warning("ClawSpeak fuzzer caught throw: #{inspect(reason)}")
    end
  end
end
