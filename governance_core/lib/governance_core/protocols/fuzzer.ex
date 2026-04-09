defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Generates random binary frames to test the UMP parser and ensure
  it handles malformed inputs gracefully without crashing.
  """
  use GenServer
  require Logger

  # Default interval for fuzzing: 5 seconds
  @interval 5_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("Starting ClawSpeak UMP Fuzzer")
    schedule_fuzz()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:fuzz, state) do
    # Generate a random binary frame
    fuzz_frame()
    schedule_fuzz()
    {:noreply, state}
  end

  defp schedule_fuzz do
    Process.send_after(self(), :fuzz, @interval)
  end

  defp fuzz_frame do
    # Use StreamData to generate random binaries
    # StreamData generators implement Enumerable, so we can use Enum.take/2 directly
    generator = StreamData.binary(min_length: 1, max_length: 20)
    [random_binary] = Enum.take(generator, 1)

    try do
      _result = GovernanceCore.Protocols.UMP.Parser.parse_frame(random_binary)
      # We don't care about the result, just that it doesn't crash the GenServer
    rescue
      e ->
        Logger.error("UMP Parser crashed on fuzzed input: #{inspect(random_binary)}, Exception: #{inspect(e)}")
    catch
      kind, reason ->
        Logger.error("UMP Parser threw/exited on fuzzed input: #{inspect(random_binary)}, Kind: #{inspect(kind)}, Reason: #{inspect(reason)}")
    end
  end
end
