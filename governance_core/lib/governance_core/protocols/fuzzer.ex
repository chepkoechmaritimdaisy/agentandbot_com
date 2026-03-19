defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Periodically generates random binary payloads using StreamData and calls GovernanceCore.Protocols.ClawSpeak.decode/1.
  This fuzzer tests the resilience of the UMP parser against invalid binary inputs.
  """
  use GenServer
  require Logger

  # Default interval: 10 seconds
  @interval 10_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
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

  defp perform_fuzz do
    payload = generate_payload()

    try do
      GovernanceCore.Protocols.ClawSpeak.decode(payload)
      Logger.debug("Fuzzer: Successfully processed payload without crashing.")
    rescue
      e ->
        Logger.error("Fuzzer: Parser rescued an exception on payload. Exception: #{inspect(e)}")
    catch
      kind, reason ->
        Logger.error("Fuzzer: Parser crashed on payload. Kind: #{inspect(kind)}, Reason: #{inspect(reason)}")
    end
  end

  defp generate_payload do
    [payload] = Enum.take(StreamData.binary(), 1)
    payload
  end
end
