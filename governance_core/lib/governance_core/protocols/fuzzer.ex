defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  A background fuzzer for the UMP Protocol Parser.
  Generates random binary payloads and tests the parser.
  """
  use GenServer
  require Logger

  # Continuous interval: 5 minutes
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
    Logger.info("Starting UMP Protocol Fuzzing...")

    # Generate 100 random binary payloads using stream_data
    payloads = StreamData.binary() |> Enum.take(100)

    Enum.each(payloads, fn payload ->
      try do
        _result = GovernanceCore.Protocols.UMP.Parser.parse_frame(payload)
      rescue
        e in MatchError ->
          Logger.error("Fuzzer: MatchError on payload #{inspect(payload)}: #{inspect(e)}")
        e in FunctionClauseError ->
          Logger.error("Fuzzer: FunctionClauseError on payload #{inspect(payload)}: #{inspect(e)}")
        e in RuntimeError ->
          Logger.error("Fuzzer: RuntimeError on payload #{inspect(payload)}: #{inspect(e)}")
        e in ArgumentError ->
          Logger.error("Fuzzer: ArgumentError on payload #{inspect(payload)}: #{inspect(e)}")
      end
    end)

    Logger.info("Finished UMP Protocol Fuzzing.")
    schedule_fuzz()
    {:noreply, state}
  end

  defp schedule_fuzz do
    Process.send_after(self(), :fuzz, @interval)
  end
end
