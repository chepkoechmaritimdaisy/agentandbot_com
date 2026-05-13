defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Continuous ClawSpeak (UMP) Fuzzing GenServer.
  Generates random binary frames using StreamData to test
  the UMP Parser for edge cases, inconsistencies, and errors.
  """
  use GenServer
  require Logger

  @interval 5 * 60 * 1000 # 5 minutes

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_fuzzing()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:fuzz, state) do
    run_fuzzer()
    schedule_fuzzing()
    {:noreply, state}
  end

  defp schedule_fuzzing do
    Process.send_after(self(), :fuzz, @interval)
  end

  defp run_fuzzer do
    Logger.info("[Fuzzer] Starting UMP fuzzing cycle...")

    # Using StreamData generator per memory directive to test parse_frame/1
    # Note: StreamData generators implement Enumerable natively.
    generator = StreamData.binary()

    generator
    |> Enum.take(100)
    |> Enum.each(fn payload ->
      try do
        GovernanceCore.Protocols.UMP.Parser.parse_frame(payload)
      rescue
        # explicitly rescuing specific errors as required by memory
        e in [MatchError, FunctionClauseError, RuntimeError, ArgumentError] ->
          Logger.error("[Fuzzer] UMP Parser crashed on payload: #{inspect(payload)}. Error: #{inspect(e)}")
      end
    end)

    Logger.info("[Fuzzer] Completed UMP fuzzing cycle.")
  end
end