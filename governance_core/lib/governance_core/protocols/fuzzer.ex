defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  A continuous fuzzer for the Universal Message Protocol (UMP) parser.
  """
  use GenServer
  require Logger

  @interval 5_000 # 5 seconds

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_fuzz()
    {:ok, state}
  end

  @impl true
  def handle_info(:fuzz, state) do
    fuzz_ump()
    schedule_fuzz()
    {:noreply, state}
  end

  defp schedule_fuzz do
    Process.send_after(self(), :fuzz, @interval)
  end

  defp fuzz_ump do
    # Generate random binary payloads using StreamData
    payloads = StreamData.binary() |> Enum.take(1)

    Enum.each(payloads, fn payload ->
      try do
        case GovernanceCore.Protocols.UMP.parse(payload) do
          {:ok, _data} ->
            Logger.debug("UMP Fuzzer: Valid payload parsed successfully.")
          {:error, reason} ->
            Logger.debug("UMP Fuzzer: Payload rejected gracefully. Reason: #{inspect(reason)}")
        end
      rescue
        e in MatchError ->
          Logger.error("UMP Fuzzer: MatchError during parse: #{inspect(e)}")
        e in FunctionClauseError ->
          Logger.error("UMP Fuzzer: FunctionClauseError during parse: #{inspect(e)}")
        e in RuntimeError ->
          Logger.error("UMP Fuzzer: RuntimeError during parse: #{inspect(e)}")
        e in ArgumentError ->
          Logger.error("UMP Fuzzer: ArgumentError during parse: #{inspect(e)}")
      end
    end)
  end
end
