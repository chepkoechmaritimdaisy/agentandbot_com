defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  A background fuzzer testing UMP parsing using StreamData generators.
  """
  use GenServer
  require Logger

  # 5 minutes in milliseconds
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
    Logger.info("Starting UMP Protocol Fuzzer...")

    StreamData.binary()
    |> Enum.take(100)
    |> Enum.each(fn payload ->
      try do
        # Passing payload to the parser
        GovernanceCore.Protocols.UMP.Parser.parse_frame(payload)
      rescue
        e in MatchError ->
          Logger.error("Fuzzer triggered MatchError: #{inspect(e)}")
        e in FunctionClauseError ->
          Logger.error("Fuzzer triggered FunctionClauseError: #{inspect(e)}")
        e in RuntimeError ->
          Logger.error("Fuzzer triggered RuntimeError: #{inspect(e)}")
        e in ArgumentError ->
          Logger.error("Fuzzer triggered ArgumentError: #{inspect(e)}")
      end
    end)
    Logger.info("Finished UMP Protocol Fuzzer iteration.")
  end
end
