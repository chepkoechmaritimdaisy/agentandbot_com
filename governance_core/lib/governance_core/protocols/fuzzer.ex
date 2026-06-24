defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Generates random binary data to fuzz the UMP parser,
  continuously checking for inconsistent pattern matching
  and ensuring it does not crash ungracefully.
  """

  use GenServer
  require Logger

  @interval 1000 # Run every 1 second

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_fuzz()
    {:ok, state}
  end

  def handle_info(:fuzz, state) do
    fuzz_parser()
    schedule_fuzz()
    {:noreply, state}
  end

  defp schedule_fuzz do
    Process.send_after(self(), :fuzz, @interval)
  end

  defp fuzz_parser do
    # Generate some random binary payload using StreamData
    payload =
      StreamData.binary()
      |> Enum.take(1)
      |> hd()

    try do
      _result = GovernanceCore.Protocols.UMP.parse(payload)
      # We don't really care about the result, just that it didn't crash
    rescue
      e in MatchError ->
        Logger.error("UMP Parser Fuzzing MatchError: #{inspect(e)} on payload #{inspect(payload)}")
      e in FunctionClauseError ->
        Logger.error("UMP Parser Fuzzing FunctionClauseError: #{inspect(e)} on payload #{inspect(payload)}")
      e in RuntimeError ->
        Logger.error("UMP Parser Fuzzing RuntimeError: #{inspect(e)} on payload #{inspect(payload)}")
      e in ArgumentError ->
        Logger.error("UMP Parser Fuzzing ArgumentError: #{inspect(e)} on payload #{inspect(payload)}")
    end
  end
end
