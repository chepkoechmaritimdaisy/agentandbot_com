defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  A GenServer that continuously fuzzes the ClawSpeak UMP Protocol parser
  with random binary data using StreamData, and logs granular errors
  without over-catching exceptions.
  """

  use GenServer
  require Logger
  alias GovernanceCore.Protocols.UMP.Parser

  # 5 seconds interval for continuous fuzzing chunks
  @interval 5_000
  @fuzz_batch_size 100

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_fuzz()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:fuzz, state) do
    perform_fuzz()
    schedule_fuzz()
    {:noreply, state}
  end

  defp schedule_fuzz do
    Process.send_after(self(), :fuzz, @interval)
  end

  defp perform_fuzz do
    generator = StreamData.binary()

    generator
    |> Enum.take(@fuzz_batch_size)
    |> Enum.each(fn bin ->
      try do
        # We don't care about the return value, just that it doesn't crash the GenServer
        _result = Parser.parse_frame(bin)
      rescue
        e in MatchError ->
          Logger.error("Fuzzer encountered MatchError with input: #{inspect(bin)}, Error: #{inspect(e)}")
        e in FunctionClauseError ->
          Logger.error("Fuzzer encountered FunctionClauseError with input: #{inspect(bin)}, Error: #{inspect(e)}")
        e in ArgumentError ->
          Logger.error("Fuzzer encountered ArgumentError with input: #{inspect(bin)}, Error: #{inspect(e)}")
        e in RuntimeError ->
          Logger.error("Fuzzer encountered RuntimeError with input: #{inspect(bin)}, Error: #{inspect(e)}")
      end
    end)
  end
end
