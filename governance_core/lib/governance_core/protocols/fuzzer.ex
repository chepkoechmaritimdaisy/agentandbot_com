defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  A GenServer that continuously fuzzes the UMP Parser to detect inconsistent pattern matching
  or unhandled exceptions by generating random binary payloads.
  """

  use GenServer
  require Logger

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

  defp perform_fuzz do
    Logger.info("Starting UMP Parser Fuzzing...")

    # Generate 1000 random binary payloads using stream_data
    payloads =
      StreamData.binary()
      |> Enum.take(1000)

    Enum.each(payloads, fn payload ->
      try do
        GovernanceCore.Protocols.UMP.Parser.parse_frame(payload)
      rescue
        e in [MatchError, FunctionClauseError, RuntimeError, ArgumentError] ->
          Logger.error("UMP Parser Fuzzing found a crash: #{inspect(e)} with payload: #{inspect(payload)}")
      end
    end)

    Logger.info("Finished UMP Parser Fuzzing")
  end
end
