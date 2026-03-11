defmodule GovernanceCore.Fuzzer do
  @moduledoc """
  A GenServer that periodically tests the GovernanceCore.Protocols.ClawSpeak.decode/1
  function with random binary data generated using stream_data to fuzz the parser.
  """
  use GenServer
  require Logger
  alias GovernanceCore.Protocols.ClawSpeak

  @interval 60_000 # Run fuzzing every minute
  @fuzz_iterations 100 # How many random payloads to test per interval

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

  defp perform_fuzzing do
    Logger.info("Starting ClawSpeak Fuzzing...")

    # We use stream_data to generate random binaries.
    # We will generate @fuzz_iterations random binaries and feed them into ClawSpeak.decode/1
    generator = StreamData.binary()

    generator
    |> Enum.take(@fuzz_iterations)
    |> Enum.each(fn random_binary ->
      try do
        case ClawSpeak.decode(random_binary) do
          {:ok, _, _} -> :ok
          {:error, _} -> :ok
        end
      rescue
        e ->
          Logger.error("ClawSpeak UMP Parser crashed during fuzzing! Exception: #{inspect(e)}, Payload: #{inspect(random_binary)}")
      catch
        kind, reason ->
          Logger.error("ClawSpeak UMP Parser caught throw/exit! #{kind}: #{inspect(reason)}, Payload: #{inspect(random_binary)}")
      end
    end)

    Logger.info("Finished ClawSpeak Fuzzing.")
  end
end
