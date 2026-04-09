defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Continuously fuzzes ClawSpeak and UMP parsers with random binary data.
  """
  use GenServer
  require Logger

  @interval 1000 # Fuzz every 1 second

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
    # Generate random binary data
    # We use StreamData generator, take 1 element
    random_binary = StreamData.binary() |> Enum.take(1) |> hd()

    # Fuzz ClawSpeak
    try do
      GovernanceCore.Protocols.ClawSpeak.decode(random_binary)
    rescue
      e -> Logger.warning("Fuzzer caught rescue in ClawSpeak.decode: #{inspect(e)}")
    catch
      type, value -> Logger.warning("Fuzzer caught catch in ClawSpeak.decode: #{inspect({type, value})}")
    end

    # Fuzz UMP
    try do
      GovernanceCore.Protocols.UMP.parse(random_binary)
    rescue
      e -> Logger.warning("Fuzzer caught rescue in UMP.parse: #{inspect(e)}")
    catch
      type, value -> Logger.warning("Fuzzer caught catch in UMP.parse: #{inspect({type, value})}")
    end
  end
end
