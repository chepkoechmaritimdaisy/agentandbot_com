defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  A GenServer that continuously fuzzes the ClawSpeak and UMP parsers by generating
  random binary data to ensure robust error handling without crashing.
  """
  use GenServer
  require Logger
  alias GovernanceCore.Protocols.{ClawSpeak, UMP}

  # 100 milliseconds
  @interval 100

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
    try do
      fuzz_data = Enum.take(StreamData.binary(), 1) |> List.first()

      _ = ClawSpeak.decode(fuzz_data)
      _ = UMP.parse(fuzz_data)
    rescue
      e ->
        Logger.error("Fuzzer encountered rescue: #{inspect(e)}")
    catch
      e ->
        Logger.error("Fuzzer encountered catch: #{inspect(e)}")
    end
  end
end
