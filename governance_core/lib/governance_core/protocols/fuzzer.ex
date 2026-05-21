defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  A background fuzzer for the UMP Parser.
  Runs continuously (every 5 minutes) to pass random binary
  chunks and detect inconsistent pattern matching or crashes.
  """
  use GenServer
  require Logger

  # 5 minutes in ms
  @interval 5 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_fuzz()
    {:ok, state}
  end

  def handle_info(:fuzz, state) do
    perform_fuzz()
    schedule_fuzz()
    {:noreply, state}
  end

  defp schedule_fuzz do
    Process.send_after(self(), :fuzz, @interval)
  end

  def perform_fuzz do
    Logger.info("Starting UMP Parser Fuzzing...")

    # Generate 100 random binary strings to test the parser
    # We use StreamData.binary() to generate the random binaries
    generator = StreamData.binary()
    chunks = Enum.take(generator, 100)

    Enum.each(chunks, fn chunk ->
      try do
        GovernanceCore.Protocols.UMP.Parser.parse_frame(chunk)
      rescue
        e in [MatchError, FunctionClauseError, RuntimeError, ArgumentError] ->
          Logger.error("UMP Parser Fuzzing found a crash: #{inspect(e)} with input: #{inspect(chunk)}")
      end
    end)

    Logger.info("UMP Parser Fuzzing completed.")
  end
end
