defmodule GovernanceCore.Protocols.Fuzzer do
  use GenServer
  require Logger

  @interval 5 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_fuzz()
    {:ok, state}
  end

  def handle_info(:fuzz, state) do
    fuzz()
    schedule_fuzz()
    {:noreply, state}
  end

  defp schedule_fuzz do
    Process.send_after(self(), :fuzz, @interval)
  end

  defp fuzz do
    try do
      Logger.info("Starting UMP Protocol Fuzzing...")

      binaries = StreamData.binary() |> Enum.take(100)

      Enum.each(binaries, fn binary ->
        GovernanceCore.Protocols.UMP.Parser.parse_frame(binary)
      end)

      Logger.info("UMP Protocol Fuzzing Completed Successfully.")
    rescue
      e in MatchError ->
        Logger.error("Fuzzing crashed due to MatchError: #{inspect(e)}")
      e in FunctionClauseError ->
        Logger.error("Fuzzing crashed due to FunctionClauseError: #{inspect(e)}")
      e in RuntimeError ->
        Logger.error("Fuzzing crashed due to RuntimeError: #{inspect(e)}")
      e in ArgumentError ->
        Logger.error("Fuzzing crashed due to ArgumentError: #{inspect(e)}")
    end
  end
end
