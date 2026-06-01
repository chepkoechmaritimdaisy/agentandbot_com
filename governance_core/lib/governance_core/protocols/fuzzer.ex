defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  A GenServer that fuzz-tests the ClawSpeak UMP Parser with random binary payloads continuously.
  """
  use GenServer
  require Logger

  @interval 5 * 60 * 1000 # 5 minutes

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
    perform_fuzzing()
    schedule_fuzz()
    {:noreply, state}
  end

  defp schedule_fuzz do
    Process.send_after(self(), :fuzz, @interval)
  end

  defp perform_fuzzing do
    # Generate random binary data
    payloads = StreamData.binary() |> Enum.take(1)

    for payload <- payloads do
      try do
        # Passing payload directly as string to UMP parser
        # UMP parses 1-byte FROM, 1-byte TO, 1-byte OP
        GovernanceCore.Protocols.UMP.Parser.parse_frame(payload)
      rescue
        e in MatchError ->
          Logger.error("Fuzzer found MatchError: #{inspect(e)} on payload: #{inspect(payload)}")
        e in FunctionClauseError ->
          Logger.error("Fuzzer found FunctionClauseError: #{inspect(e)} on payload: #{inspect(payload)}")
        e in RuntimeError ->
          Logger.error("Fuzzer found RuntimeError: #{inspect(e)} on payload: #{inspect(payload)}")
        e in ArgumentError ->
          Logger.error("Fuzzer found ArgumentError: #{inspect(e)} on payload: #{inspect(payload)}")
      end
    end
  end
end
