defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Generates random binary data to test the GovernanceCore.Protocols.UMP.Parser and ensure
  it can safely handle arbitrary payloads without crashing.
  """
  use GenServer
  require Logger

  @interval 60_000 # Run fuzzing every 60 seconds

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_fuzz()
    {:ok, state}
  end

  def handle_info(:fuzz, state) do
    perform_fuzzing()
    schedule_fuzz()
    {:noreply, state}
  end

  defp schedule_fuzz do
    Process.send_after(self(), :fuzz, @interval)
  end

  def perform_fuzzing do
    # Generate 10 random binaries and pass them to the parser
    # We use StreamData.binary() and take 10 elements since StreamData generators implement Enumerable
    StreamData.binary()
    |> Enum.take(10)
    |> Enum.each(fn payload ->
      try do
        GovernanceCore.Protocols.UMP.Parser.parse_frame(payload)
      rescue
        e ->
          Logger.warning("UMP Parser Fuzzing Exception: #{inspect(e)} with payload: #{inspect(payload)}")
      catch
        kind, value ->
          Logger.warning("UMP Parser Fuzzing Caught #{kind}: #{inspect(value)} with payload: #{inspect(payload)}")
      end
    end)
  end
end
