defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  GenServer that fuzzes the UMP Parser to ensure it can handle random invalid binary data
  without crashing or misbehaving.
  """
  use GenServer
  require Logger

  @interval 5 * 60 * 1000 # 5 minutes

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_fuzzing()
    {:ok, state}
  end

  @impl true
  def handle_info(:fuzz, state) do
    Logger.info("Starting UMP Fuzzing...")

    # Generate random binary data using stream_data and take 10 samples
    samples = StreamData.binary() |> Enum.take(10)

    Enum.each(samples, fn binary_data ->
      try do
        GovernanceCore.Protocols.UMP.Parser.parse_frame(binary_data)
      rescue
        e in [MatchError, FunctionClauseError, RuntimeError] ->
          Logger.error("Fuzzer caught an exception: #{inspect(e)}")
      catch
        kind, reason ->
          Logger.error("Fuzzer caught #{kind}: #{inspect(reason)}")
      end
    end)

    schedule_fuzzing()
    {:noreply, state}
  end

  defp schedule_fuzzing do
    Process.send_after(self(), :fuzz, @interval)
  end
end
