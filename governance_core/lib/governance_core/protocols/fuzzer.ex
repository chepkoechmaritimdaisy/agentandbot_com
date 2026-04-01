defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  A GenServer that continuously fuzzes the UMP Parser to test for inconsistent pattern matching
  or other crashes when provided with malformed or boundary-case data.
  """
  use GenServer
  require Logger
  alias GovernanceCore.Protocols.UMP.Parser

  # 1 hour
  @interval 60 * 60 * 1000

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

  def perform_fuzzing do
    Logger.info("Starting Continuous Fuzzing of UMP Parser...")

    generator = StreamData.binary()

    generator
    |> Enum.take(1000)
    |> Enum.each(fn bin ->
      try do
        Parser.parse_frame(bin)
      rescue
        e ->
          Logger.error("UMP Parser crashed on fuzzing input. Error: #{inspect(e)}")
      catch
        kind, value ->
          Logger.error("UMP Parser threw an error on fuzzing input. #{kind}: #{inspect(value)}")
      end
    end)

    Logger.info("Finished Fuzzing of UMP Parser.")
  end
end
