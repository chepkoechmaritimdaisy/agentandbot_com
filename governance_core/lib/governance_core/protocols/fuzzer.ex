defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  A GenServer that continuously fuzzes the UMP Parser to find inconsistent pattern matching.
  """
  use GenServer
  require Logger

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
    run_fuzzer()
    schedule_fuzzing()
    {:noreply, state}
  end

  defp schedule_fuzzing do
    Process.send_after(self(), :fuzz, @interval)
  end

  defp run_fuzzer do
    Logger.info("Starting UMP Parser Fuzzing...")

    try do
      # Take a sample of 100 random binaries to fuzz the parser
      binary_generator = StreamData.binary()

      Enum.each(Enum.take(binary_generator, 100), fn random_binary ->
        try do
          # We just care that it doesn't crash, the output value doesn't matter
          _result = GovernanceCore.Protocols.UMP.Parser.parse_frame(random_binary)
        rescue
          e -> Logger.error("UMP Parser Fuzzing Rescue Caught: #{inspect(e)}")
        catch
          kind, reason -> Logger.error("UMP Parser Fuzzing Catch Caught: #{kind} #{inspect(reason)}")
        end
      end)

      Logger.info("UMP Parser Fuzzing completed successfully.")
    rescue
      e -> Logger.error("Fuzzer execution failed: #{inspect(e)}")
    end
  end
end
