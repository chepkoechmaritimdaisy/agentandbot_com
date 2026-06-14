defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Continuously fuzz tests the ClawSpeak protocol parser using random binaries.
  """
  use GenServer
  require Logger

  # Time between fuzz batches (in ms)
  @fuzz_interval 5000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_fuzz()
    {:ok, state}
  end

  def handle_info(:fuzz, state) do
    run_fuzz_batch()
    schedule_fuzz()
    {:noreply, state}
  end

  defp schedule_fuzz do
    Process.send_after(self(), :fuzz, @fuzz_interval)
  end

  defp run_fuzz_batch do
    # Generate 100 random binary payloads using stream_data
    payloads =
      StreamData.binary()
      |> Enum.take(100)

    Enum.each(payloads, fn payload ->
      try do
        GovernanceCore.Protocols.ClawSpeak.decode(payload)
      rescue
        e in [MatchError, FunctionClauseError, RuntimeError, ArgumentError] ->
          Logger.error("Fuzzer found a crash in ClawSpeak.decode/1 with payload #{inspect(payload)}: #{inspect(e)}")
      catch
        kind, value ->
           Logger.error("Fuzzer caught #{inspect(kind)} in ClawSpeak.decode/1 with payload #{inspect(payload)}: #{inspect(value)}")
      end
    end)
  end
end
