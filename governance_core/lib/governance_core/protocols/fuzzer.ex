defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  GenServer that periodically fuzzes the UMP Parser with random binaries.
  """
  use GenServer
  require Logger

  @interval 1000 # 1 second

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
    fuzz_parser()
    schedule_fuzz()
    {:noreply, state}
  end

  defp schedule_fuzz do
    Process.send_after(self(), :fuzz, @interval)
  end

  defp fuzz_parser do
    # Generate a random binary using StreamData
    binaries = Enum.take(StreamData.binary(), 1)

    Enum.each(binaries, fn bin ->
      try do
        GovernanceCore.Protocols.UMP.Parser.parse_frame(bin)
      rescue
        e ->
          Logger.error("Fuzzer encountered rescue: #{inspect(e)}")
      catch
        kind, value ->
          Logger.error("Fuzzer caught: #{kind} #{inspect(value)}")
      end
    end)
  end
end
