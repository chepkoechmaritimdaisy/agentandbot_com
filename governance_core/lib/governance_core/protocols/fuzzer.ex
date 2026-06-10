defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Periodically generates random binary payloads to fuzz the UMP parser.
  """
  use GenServer
  require Logger

  # 5 minutes in milliseconds
  @interval 5 * 60 * 1000

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
    perform_fuzz()
    schedule_fuzz()
    {:noreply, state}
  end

  defp schedule_fuzz do
    Process.send_after(self(), :fuzz, @interval)
  end

  def perform_fuzz do
    # Generate 100 random payloads of lengths up to 10 bytes
    payloads =
      StreamData.binary()
      |> Enum.take(100)
      |> Enum.map(fn bin -> binary_part(bin, 0, min(byte_size(bin), 10)) end)

    Enum.each(payloads, fn payload ->
      try do
        GovernanceCore.Protocols.UMP.Parser.parse_frame(payload)
      rescue
        e in MatchError ->
          Logger.error("UMP Parser Fuzzer Crash (MatchError): #{inspect(e)}")

        e in FunctionClauseError ->
          Logger.error("UMP Parser Fuzzer Crash (FunctionClauseError): #{inspect(e)}")

        e in RuntimeError ->
          Logger.error("UMP Parser Fuzzer Crash (RuntimeError): #{inspect(e)}")

        e in ArgumentError ->
          Logger.error("UMP Parser Fuzzer Crash (ArgumentError): #{inspect(e)}")
      end
    end)
  end
end
