defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Continuously fuzzes the UMP Parser to find edge cases and unhandled exceptions.
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

  def perform_fuzz do
    # Generate 100 random binary frames
    StreamData.binary()
    |> Enum.take(100)
    |> Enum.each(fn frame ->
      try do
        GovernanceCore.Protocols.UMP.Parser.parse_frame(frame)
      rescue
        e in [MatchError, FunctionClauseError, RuntimeError, ArgumentError] ->
          Logger.error("UMP Parser crashed on frame: #{inspect(frame)}. Error: #{inspect(e)}")
      catch
        kind, reason ->
          Logger.error("UMP Parser caught error on frame: #{inspect(frame)}. Kind: #{inspect(kind)}, Reason: #{inspect(reason)}")
      end
    end)
  end
end
