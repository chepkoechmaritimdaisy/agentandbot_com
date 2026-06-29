defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  ClawSpeak (UMP) Fuzzing GenServer.
  Generates random binary payloads and tests the UMP parser,
  continuously monitoring for protocol breakdown or inconsistent matching.
  """
  use GenServer
  require Logger

  @interval 5_000 # Fuzz every 5 seconds for demonstration

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
    fuzz_ump_parser()
    schedule_fuzz()
    {:noreply, state}
  end

  defp schedule_fuzz do
    Process.send_after(self(), :fuzz, @interval)
  end

  defp fuzz_ump_parser do
    Logger.debug("Generating ClawSpeak fuzzing payloads...")
    # Generate random binary data using stream_data
    payloads = StreamData.binary() |> Enum.take(10)

    Enum.each(payloads, fn payload ->
      try do
        # Simulating UMP parsing logic
        # In a real scenario, this would call the actual parser module
        dummy_parse(payload)
      rescue
        e in MatchError ->
          Logger.error("UMP Fuzzing detected MatchError: #{inspect(e)} with payload: #{inspect(payload)}")
        e in FunctionClauseError ->
          Logger.error("UMP Fuzzing detected FunctionClauseError: #{inspect(e)} with payload: #{inspect(payload)}")
        e in RuntimeError ->
          Logger.error("UMP Fuzzing detected RuntimeError: #{inspect(e)} with payload: #{inspect(payload)}")
        e in ArgumentError ->
          Logger.error("UMP Fuzzing detected ArgumentError: #{inspect(e)} with payload: #{inspect(payload)}")
      end
    end)
  end

  # A dummy parse function to simulate parser crashes
  defp dummy_parse(<<1, _rest::binary>>) do
    # Simulate a crash if binary starts with 1
    raise RuntimeError, message: "Simulated parse crash for UMP protocol"
  end

  defp dummy_parse(_payload) do
    :ok
  end
end
