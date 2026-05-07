defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Provides continuous fuzzing and stress testing for the UMP Protocol parser.
  """
  use GenServer
  require Logger
  alias GovernanceCore.Protocols.UMP.Parser

  @interval 5 * 60 * 1000 # 5 minutes

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_fuzz()
    {:ok, state}
  end

  def handle_info(:fuzz, state) do
    fuzz_ump_parser(1000)
    schedule_fuzz()
    {:noreply, state}
  end

  defp schedule_fuzz do
    Process.send_after(self(), :fuzz, @interval)
  end

  def fuzz_ump_parser(num_cases \\ 10_000) do
    Logger.info("Starting UMP Parser Fuzzing with #{num_cases} cases...")

    StreamData.binary()
    |> Enum.take(num_cases)
    |> Enum.each(fn bin ->
      try do
        # Call the parser and just let it match or return
        _result = Parser.parse_frame(bin)
      rescue
        e in MatchError ->
          Logger.error("Fuzzing caught MatchError on input #{inspect(bin)}: #{inspect(e)}")

        e in FunctionClauseError ->
          Logger.error("Fuzzing caught FunctionClauseError on input #{inspect(bin)}: #{inspect(e)}")

        e in RuntimeError ->
          Logger.error("Fuzzing caught RuntimeError on input #{inspect(bin)}: #{inspect(e)}")

        e in ArgumentError ->
          Logger.error("Fuzzing caught ArgumentError on input #{inspect(bin)}: #{inspect(e)}")
      end
    end)

    Logger.info("Completed UMP Parser Fuzzing.")
    :ok
  end
end
