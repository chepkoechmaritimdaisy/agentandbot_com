defmodule GovernanceCore.Protocols.Fuzzer do
  use GenServer
  require Logger

  @interval 5 * 60 * 1000 # 5 minutes
  @sample_size 10

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
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
    # Generate random binaries
    StreamData.binary()
    |> Enum.take(@sample_size)
    |> Enum.each(fn payload ->
      try do
        GovernanceCore.Protocols.UMP.Parser.parse_frame(payload)
      rescue
        e -> Logger.warning("Fuzzer caught rescue: #{inspect(e)}")
      catch
        kind, value -> Logger.warning("Fuzzer caught #{kind}: #{inspect(value)}")
      end
    end)
  end
end
