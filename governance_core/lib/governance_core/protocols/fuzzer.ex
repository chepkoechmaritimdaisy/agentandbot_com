defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Runs continuous fuzzing tests on the ClawSpeak (UMP) protocol parser.
  """
  use GenServer
  require Logger

  # 5 minutes in milliseconds
  @interval 5 * 60 * 1000

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
    Logger.info("Starting Continuous ClawSpeak Fuzzing...")

    # Generate 100 random binary inputs
    for _ <- 1..100 do
      length = :rand.uniform(64)
      binary_data = :crypto.strong_rand_bytes(length)

      try do
        _result = GovernanceCore.Protocols.UMP.Parser.parse_frame(binary_data)
        # We don't assert on result, we just want to make sure it doesn't crash the GenServer
      rescue
        e in [MatchError, FunctionClauseError, RuntimeError, ArgumentError] ->
          Logger.warning("Fuzzer caught expected exception: #{inspect(e)} for payload #{inspect(binary_data)}")
      end
    end

    Logger.info("Continuous ClawSpeak Fuzzing Completed.")
  end
end
