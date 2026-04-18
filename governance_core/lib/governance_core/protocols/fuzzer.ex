defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  A GenServer that continuously fuzzes the UMP Parser to detect inconsistent pattern matching.
  Runs every 5 minutes and uses StreamData to generate random binary payloads.
  """

  use GenServer
  require Logger

  # 5 minutes
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
    Logger.debug("Starting UMP Parser Fuzzing...")

    generator = StreamData.binary()

    generator
    |> Enum.take(100)
    |> Enum.each(fn payload ->
      try do
        _result = GovernanceCore.Protocols.UMP.Parser.parse_frame(payload)
      rescue
        e ->
          Logger.error("Fuzzer caught rescue error: #{inspect(e)} for payload: #{inspect(payload)}")
      catch
        kind, reason ->
          Logger.error("Fuzzer caught #{kind} error: #{inspect(reason)} for payload: #{inspect(payload)}")
      end
    end)

    Logger.debug("UMP Parser Fuzzing completed.")
  end
end
