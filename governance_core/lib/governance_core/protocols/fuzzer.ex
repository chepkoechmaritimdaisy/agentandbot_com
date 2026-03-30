defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Automated Fuzzer for ClawSpeak and UMP protocols.
  Runs as a GenServer and periodically generates random binary data
  to test the limits of the protocol parsers.
  """
  use GenServer
  require Logger
  alias GovernanceCore.Protocols.{ClawSpeak, UMP}
  import StreamData, only: [binary: 0]

  # Fuzz every 1 minute
  @interval 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_fuzzing()
    Logger.info("GovernanceCore.Protocols.Fuzzer started.")
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
    # Generate 100 random binaries to test the parsers
    generator = binary()
    samples = Enum.take(generator, 100)

    Enum.each(samples, fn data ->
      test_clawspeak(data)
      test_ump(data)
    end)
  end

  defp test_clawspeak(data) do
    try do
      ClawSpeak.decode(data)
    rescue
      e ->
        Logger.error("ClawSpeak decoder crash on input #{inspect(data)}: #{inspect(e)}")
    catch
      type, value ->
        Logger.error("ClawSpeak decoder throw/exit on input #{inspect(data)}: #{inspect({type, value})}")
    end
  end

  defp test_ump(data) do
    try do
      UMP.parse(data)
    rescue
      e ->
        Logger.error("UMP parser crash on input #{inspect(data)}: #{inspect(e)}")
    catch
      type, value ->
        Logger.error("UMP parser throw/exit on input #{inspect(data)}: #{inspect({type, value})}")
    end
  end
end
