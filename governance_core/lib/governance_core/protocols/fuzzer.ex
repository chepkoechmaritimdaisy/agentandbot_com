defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  A GenServer that continuously fuzzes and stress-tests the ClawSpeak and UMP protocols.
  It generates random binary data using StreamData and feeds it to the decoders to ensure
  they don't crash under invalid inputs.
  """
  use GenServer
  require Logger

  @interval 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_fuzz()
    {:ok, state}
  end

  def handle_info(:fuzz, state) do
    fuzz()
    schedule_fuzz()
    {:noreply, state}
  end

  defp schedule_fuzz do
    Process.send_after(self(), :fuzz, @interval)
  end

  defp fuzz do
    # Generate random binary inputs using StreamData
    Enum.take(StreamData.binary(), 10)
    |> Enum.each(fn bin ->
      # Fuzz ClawSpeak decoder
      try do
        GovernanceCore.Protocols.ClawSpeak.decode(bin)
      rescue
        e -> Logger.warning("Fuzzer found rescue in ClawSpeak: #{inspect(e)}")
      catch
        kind, value -> Logger.warning("Fuzzer found catch in ClawSpeak: #{inspect(kind)} #{inspect(value)}")
      end

      # Fuzz UMP parser
      try do
        GovernanceCore.Protocols.UMP.parse(bin)
      rescue
        e -> Logger.warning("Fuzzer found rescue in UMP: #{inspect(e)}")
      catch
        kind, value -> Logger.warning("Fuzzer found catch in UMP: #{inspect(kind)} #{inspect(value)}")
      end
    end)
  end
end
