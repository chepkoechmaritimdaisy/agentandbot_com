defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Generates random binary payloads to stress-test the UMP Parser continually.
  """
  use GenServer
  require Logger

  # Default interval: 5 seconds
  @interval 5_000

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
    # Generate a random binary of 1 to 20 bytes
    length = :rand.uniform(20)
    payload = StreamData.binary() |> Enum.take(length) |> IO.iodata_to_binary()

    try do
      result = GovernanceCore.Protocols.UMP.Parser.parse_frame(payload)
      case result do
        {:ok, _} -> Logger.debug("Fuzzer: Valid format (unexpected but okay)")
        {:error, _} -> Logger.debug("Fuzzer: Handled gracefully")
      end
    rescue
      e in [MatchError, FunctionClauseError, RuntimeError, ArgumentError] ->
        Logger.error("Fuzzer: UMP Parser crashed on payload #{inspect(payload)} - #{Exception.message(e)}")
    end
  end
end
