defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Periodically generates random ClawSpeak and UMP binary frames using `stream_data` generators
  and passes them to the parsers to ensure the protocols handle invalid data without crashing.
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
    perform_fuzzing()
    schedule_fuzzing()
    {:noreply, state}
  end

  defp schedule_fuzzing do
    Process.send_after(self(), :fuzz, @interval)
  end

  def perform_fuzzing do
    Logger.debug("Starting Fuzzing for ClawSpeak and UMP protocols...")

    # Run fuzzing using StreamData generators (take 10 samples per run)
    Enum.each(Enum.take(StreamData.binary(), 10), fn binary ->
      try do
        GovernanceCore.Protocols.ClawSpeak.decode(binary)
      rescue
        e -> Logger.error("Fuzzer found rescue error in ClawSpeak.decode/1: #{inspect(e)}")
      catch
        kind, reason -> Logger.error("Fuzzer found catch error in ClawSpeak.decode/1: #{inspect({kind, reason})}")
      end

      try do
        GovernanceCore.Protocols.UMP.Parser.parse_frame(binary)
      rescue
        e -> Logger.error("Fuzzer found rescue error in UMP.Parser.parse_frame/1: #{inspect(e)}")
      catch
        kind, reason -> Logger.error("Fuzzer found catch error in UMP.Parser.parse_frame/1: #{inspect({kind, reason})}")
      end
    end)
  end
end
