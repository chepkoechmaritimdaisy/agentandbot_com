defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  A GenServer that fuzzes the UMP Parser continuously to find inconsistencies or parsing crashes.
  """
  use GenServer
  require Logger

  # Continuous running interval according to project memory (5 minutes)
  @interval 5 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_fuzz()
    {:ok, state}
  end

  @impl true
  def handle_info(:fuzz, state) do
    perform_fuzzing()
    schedule_fuzz()
    {:noreply, state}
  end

  defp schedule_fuzz do
    Process.send_after(self(), :fuzz, @interval)
  end

  defp perform_fuzzing do
    Logger.info("Starting continuous fuzzing of UMP Parser...")

    # Take a few random binary payloads from stream_data
    generator = StreamData.binary()
    payloads = Enum.take(generator, 100)

    Enum.each(payloads, fn payload ->
      try do
        case GovernanceCore.Protocols.UMP.Parser.parse_frame(payload) do
          {:ok, _} -> :ok
          {:error, _} -> :ok
        end
      rescue
        e in [MatchError, FunctionClauseError, RuntimeError, ArgumentError] ->
          Logger.error("UMP Parser crashed on payload: #{inspect(payload)} with error: #{inspect(e)}")
      end
    end)
    Logger.info("Completed continuous fuzzing.")
  end
end
