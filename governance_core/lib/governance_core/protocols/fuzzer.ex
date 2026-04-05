defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  A GenServer that continuously fuzz-tests the ClawSpeak UMP protocol parsers.
  Generates random binary payloads and feeds them to parsers to catch crashes
  or inconsistent pattern matching issues without human intervention.
  """
  use GenServer
  require Logger

  # Run a fuzz burst every 5 seconds
  @interval 5_000
  @burst_size 100

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_fuzz()
    {:ok, state}
  end

  def handle_info(:fuzz, state) do
    run_fuzz_burst()
    schedule_fuzz()
    {:noreply, state}
  end

  defp schedule_fuzz do
    Process.send_after(self(), :fuzz, @interval)
  end

  defp run_fuzz_burst do
    # Generate random binary data using StreamData natively (without calling stream/1)
    generator = StreamData.binary()

    # We take @burst_size random items from the generator
    samples = Enum.take(generator, @burst_size)

    Enum.each(samples, fn binary_payload ->
      fuzz_parse(binary_payload)
    end)
  end

  defp fuzz_parse(payload) do
    try do
      # Attempt to parse payload using the UMP parser
      # We discard the result, we only care if it crashes
      _ = GovernanceCore.Protocols.UMP.parse(payload)

      # We could also fuzz the ClawSpeak decoder
      _ = GovernanceCore.Protocols.ClawSpeak.decode(payload)
    rescue
      e ->
        Logger.error("Fuzzer found a crash! Rescue: #{inspect(e)}")
    catch
      kind, value ->
        Logger.error("Fuzzer found a crash! Catch: #{inspect(kind)} #{inspect(value)}")
    end
  end
end
