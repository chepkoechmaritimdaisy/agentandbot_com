defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Periodically fuzzes ClawSpeak.decode/1 using random binary data.
  """
  use GenServer
  require Logger

  # Run fuzzer every 10 seconds
  @fuzz_interval 10_000
  # Fuzz 100 samples per interval
  @fuzz_samples 100

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_fuzzing()
    {:ok, state}
  end

  def handle_info(:fuzz, state) do
    fuzz_clawspeak()
    schedule_fuzzing()
    {:noreply, state}
  end

  defp schedule_fuzzing do
    Process.send_after(self(), :fuzz, @fuzz_interval)
  end

  defp fuzz_clawspeak do
    # StreamData generators implement Enumerable natively.
    # Use Enum.take/2 instead of StreamData.stream/1.
    generator = StreamData.binary()

    generator
    |> Enum.take(@fuzz_samples)
    |> Enum.each(fn binary_data ->
      try do
        GovernanceCore.Protocols.ClawSpeak.decode(binary_data)
      rescue
        e ->
          Logger.error("Fuzzer encountered rescue: #{inspect(e)} with input: #{inspect(binary_data)}")
      catch
        kind, reason ->
          Logger.error("Fuzzer encountered catch: #{kind}: #{inspect(reason)} with input: #{inspect(binary_data)}")
      end
    end)
  end
end
