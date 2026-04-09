defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  GenServer that continuously tests the UMP Parser using generated random UMP frames.
  It generates valid and invalid binary data using stream_data natively.
  """
  use GenServer
  require Logger

  alias GovernanceCore.Protocols.UMP.Parser

  # Run fuzzer continuously but wait a bit between fuzz batches
  @fuzz_interval 5000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_fuzz()
    {:ok, state}
  end

  def handle_info(:fuzz, state) do
    perform_fuzzing()
    schedule_fuzz()
    {:noreply, state}
  end

  defp schedule_fuzz do
    Process.send_after(self(), :fuzz, @fuzz_interval)
  end

  def perform_fuzzing do
    # Memory: "In the StreamData library, generators implement the Enumerable protocol natively; use Enum.take(generator, n) directly instead of attempting to call a non-existent StreamData.stream/1 function."
    # Let's generate random UMP frames.
    generator = StreamData.binary(min_length: 1, max_length: 20)

    # Take 100 random binaries
    Enum.take(generator, 100)
    |> Enum.each(fn bin ->
      try do
        # Memory: "When fuzzing parsers in GenServers (e.g., GovernanceCore.Protocols.Fuzzer), parsing operations are wrapped in try/rescue/catch blocks to ensure invalid binary inputs do not crash the isolated processes."
        case Parser.parse_frame(bin) do
          {:ok, _} -> :ok
          {:error, _} -> :ok
          # Inconsistent pattern matching shouldn't happen but we catch unexpected
          other ->
            Logger.warning("Fuzzer: Inconsistent return from parse_frame: #{inspect(other)} for bin: #{inspect(bin)}")
        end
      rescue
        e ->
          Logger.error("Fuzzer crashed parser: #{inspect(e)} for bin: #{inspect(bin)}")
      catch
        kind, value ->
          Logger.error("Fuzzer caught #{kind}: #{inspect(value)} for bin: #{inspect(bin)}")
      end
    end)
  end
end
