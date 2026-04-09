defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Automated fuzzer for testing the resilience of ClawSpeak and UMP protocols.
  Runs as a GenServer in the supervision tree.
  """

  use GenServer
  require Logger

  # Default fuzzing interval: 5 seconds
  @interval 5_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_fuzz()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:fuzz, state) do
    # Perform fuzzing on ClawSpeak and UMP
    fuzz_clawspeak()
    fuzz_ump()

    schedule_fuzz()
    {:noreply, state}
  end

  defp schedule_fuzz do
    Process.send_after(self(), :fuzz, @interval)
  end

  defp fuzz_clawspeak do
    # Take 10 random binaries from the StreamData generator
    binaries = Enum.take(StreamData.binary(), 10)

    for binary <- binaries do
      try do
        # We don't care about the result, just that it doesn't crash the GenServer
        _ = GovernanceCore.Protocols.ClawSpeak.decode(binary)
      rescue
        e ->
          Logger.warning("ClawSpeak fuzzer caught exception: #{inspect(e)} with input: #{inspect(binary)}")
      catch
        kind, reason ->
          Logger.warning("ClawSpeak fuzzer caught #{kind}: #{inspect(reason)} with input: #{inspect(binary)}")
      end
    end
  end

  defp fuzz_ump do
    # Take 10 random binaries from the StreamData generator
    binaries = Enum.take(StreamData.binary(), 10)

    for binary <- binaries do
      try do
        # We don't care about the result, just that it doesn't crash the GenServer
        _ = GovernanceCore.Protocols.UMP.parse(binary)
      rescue
        e ->
          Logger.warning("UMP fuzzer caught exception: #{inspect(e)} with input: #{inspect(binary)}")
      catch
        kind, reason ->
          Logger.warning("UMP fuzzer caught #{kind}: #{inspect(reason)} with input: #{inspect(binary)}")
      end
    end
  end
end
