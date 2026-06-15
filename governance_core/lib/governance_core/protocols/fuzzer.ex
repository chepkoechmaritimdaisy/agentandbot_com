defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  A GenServer that periodically fuzz tests the UMP Parser.
  """
  use GenServer
  require Logger
  alias GovernanceCore.Protocols.UMP.Parser

  @interval 10_000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_fuzz()
    {:ok, state}
  end

  def handle_info(:fuzz, state) do
    fuzz_test()
    schedule_fuzz()
    {:noreply, state}
  end

  defp schedule_fuzz do
    Process.send_after(self(), :fuzz, @interval)
  end

  defp fuzz_test do
    # Generate 100 random binary sequences
    binaries = StreamData.binary() |> Enum.take(100)

    Enum.each(binaries, fn bin ->
      try do
        _ = Parser.parse_frame(bin)
      rescue
        e in [MatchError, FunctionClauseError, RuntimeError, ArgumentError] ->
          Logger.error("UMP Parser crashed on fuzzer payload: #{inspect(bin)}, Error: #{inspect(e)}")
      end
    end)
  end
end
