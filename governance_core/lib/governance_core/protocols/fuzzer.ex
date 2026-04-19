defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  A GenServer that continuously tests the ClawSpeak and UMP parsers by fuzzing them with
  random binary data. It helps ensure that the parsers do not crash when given invalid
  or unexpected inputs.
  """

  use GenServer
  require Logger

  # 5 minutes in milliseconds
  @interval 5 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
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
    Logger.debug("Starting Fuzzer cycle...")

    # Generate random binaries using stream_data and take 100 samples
    binaries = StreamData.binary() |> Enum.take(100)

    Enum.each(binaries, fn bin ->
      fuzz_ump(bin)
      fuzz_clawspeak(bin)
    end)
  end

  defp fuzz_ump(bin) do
    try do
      GovernanceCore.Protocols.UMP.Parser.parse_frame(bin)
    rescue
      e -> Logger.warning("UMP Parser crash avoided: #{inspect(e)}")
    catch
      type, value -> Logger.warning("UMP Parser caught: #{inspect(type)} #{inspect(value)}")
    end
  end

  defp fuzz_clawspeak(bin) do
    try do
      GovernanceCore.Protocols.ClawSpeak.decode(bin)
    rescue
      e -> Logger.warning("ClawSpeak Parser crash avoided: #{inspect(e)}")
    catch
      type, value -> Logger.warning("ClawSpeak Parser caught: #{inspect(type)} #{inspect(value)}")
    end
  end
end
