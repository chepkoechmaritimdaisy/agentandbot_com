defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Continuous ClawSpeak (UMP) Fuzzing GenServer.
  Generates random binary payloads and tests the UMP Parser to ensure it doesn't crash on invalid data.
  """
  use GenServer
  require Logger

  @interval 5 * 60 * 1000 # 5 minutes

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
    Logger.info("Starting ClawSpeak (UMP) Fuzzing...")

    # Generate 100 random binary payloads using StreamData
    payloads = Enum.take(StreamData.binary(), 100)

    Enum.each(payloads, fn payload ->
      try do
        GovernanceCore.Protocols.UMP.Parser.parse_frame(payload)
      rescue
        e in [MatchError, FunctionClauseError, RuntimeError, ArgumentError] ->
          Logger.error("Fuzzer caught exception: #{inspect(e)} on payload: #{inspect(payload)}")
      end
    end)

    Logger.info("ClawSpeak (UMP) Fuzzing completed.")
  end
end
