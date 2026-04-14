defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Generates random binary data to test the limits of the ClawSpeak (Gibberlink) UMP protocol parser.
  Continuously monitors for parsing crashes without manual intervention.
  """
  use GenServer
  require Logger

  # 5 minutes interval
  @interval 5 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_fuzzing()
    {:ok, state}
  end

  @impl true
  def handle_info(:fuzz, state) do
    perform_fuzzing()
    schedule_fuzzing()
    {:noreply, state}
  end

  defp schedule_fuzzing do
    Process.send_after(self(), :fuzz, @interval)
  end

  defp perform_fuzzing do
    Logger.info("Starting UMP Fuzzing...")

    # Generate 100 random binary inputs
    fuzz_inputs = StreamData.binary() |> Enum.take(100)

    Enum.each(fuzz_inputs, fn input ->
      try do
        _result = GovernanceCore.Protocols.UMP.Parser.parse_frame(input)
        # We don't care if it's :ok or :error, just that it doesn't crash
      rescue
        e -> Logger.error("Fuzzer encountered rescue: #{inspect(e)}")
      catch
        kind, value -> Logger.error("Fuzzer encountered catch: #{inspect(kind)} #{inspect(value)}")
      end
    end)

    Logger.info("UMP Fuzzing completed.")
  end
end
