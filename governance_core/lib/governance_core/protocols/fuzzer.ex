defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  A GenServer that randomly generates binary data to fuzz the UMP Parser.
  Runs every 5 minutes and uses stream_data to generate binaries.
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

  def perform_fuzz do
    Logger.info("Starting ClawSpeak Fuzzer...")

    # Generate 100 random binaries using stream_data
    binaries = Enum.take(StreamData.binary(), 100)

    Enum.each(binaries, fn bin ->
      try do
        GovernanceCore.Protocols.UMP.Parser.parse_frame(bin)
      rescue
        e -> Logger.warning("Fuzzer caused a rescue error in parser: #{inspect(e)}")
      catch
        e -> Logger.warning("Fuzzer caused a catch error in parser: #{inspect(e)}")
      end
    end)

    Logger.info("ClawSpeak Fuzzer completed.")
  end
end
