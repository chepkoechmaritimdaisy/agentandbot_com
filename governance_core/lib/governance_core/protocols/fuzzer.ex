defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  A GenServer that continuously fuzzes ClawSpeak and UMP parsers in the background
  to detect parsing crashes or protocol degradation without crashing the main application.
  """
  use GenServer
  require Logger

  # Test every minute
  @interval 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_fuzz()
    {:ok, state}
  end

  def handle_info(:fuzz, state) do
    perform_fuzzing()
    schedule_fuzz()
    {:noreply, state}
  end

  defp schedule_fuzz do
    Process.send_after(self(), :fuzz, @interval)
  end

  defp perform_fuzzing do
    Logger.info("Starting Fuzzing for UMP and ClawSpeak...")

    # Generate 100 random binary payloads using stream_data
    # Note: StreamData generators are natively Enumerable
    payloads = Enum.take(StreamData.binary(), 100)

    Enum.each(payloads, fn payload ->
      # Fuzz UMP parser
      try do
        GovernanceCore.Protocols.UMP.parse(payload)
      rescue
        e -> Logger.error("Fuzzer found a crash in UMP.parse/1: #{inspect(e)} with payload: #{inspect(payload)}")
      catch
        kind, reason -> Logger.error("Fuzzer caught #{kind} in UMP.parse/1: #{inspect(reason)} with payload: #{inspect(payload)}")
      end

      # Fuzz ClawSpeak decoder
      try do
        GovernanceCore.Protocols.ClawSpeak.decode(payload)
      rescue
        e -> Logger.error("Fuzzer found a crash in ClawSpeak.decode/1: #{inspect(e)} with payload: #{inspect(payload)}")
      catch
        kind, reason -> Logger.error("Fuzzer caught #{kind} in ClawSpeak.decode/1: #{inspect(reason)} with payload: #{inspect(payload)}")
      end
    end)

    Logger.info("Fuzzing cycle complete.")
  end
end
