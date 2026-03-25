defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  A GenServer that periodically fuzzes ClawSpeak and UMP parsers with random
  binary data to ensure they don't crash from inconsistent pattern matching.
  """

  use GenServer
  require Logger

  # Default interval of 1 minute
  @interval 60_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval, @interval)
    schedule_fuzz(interval)
    {:ok, %{interval: interval}}
  end

  @impl true
  def handle_info(:fuzz, state) do
    Logger.info("Starting ClawSpeak & UMP fuzzing cycle...")
    run_fuzz_cycle()
    schedule_fuzz(state.interval)
    {:noreply, state}
  end

  defp schedule_fuzz(interval) do
    Process.send_after(self(), :fuzz, interval)
  end

  defp run_fuzz_cycle do
    # Generate 100 random binary payloads and try to parse them
    generator = StreamData.binary()

    Enum.take(generator, 100)
    |> Enum.each(fn payload ->
      fuzz_clawspeak(payload)
      fuzz_ump(payload)
    end)
  end

  defp fuzz_clawspeak(payload) do
    try do
      _result = GovernanceCore.Protocols.ClawSpeak.decode(payload)
      :ok
    rescue
      e ->
        Logger.error("ClawSpeak decoder crashed on payload: #{inspect(payload)}, error: #{inspect(e)}")
    catch
      kind, reason ->
        Logger.error("ClawSpeak decoder threw #{kind}: #{inspect(reason)} on payload: #{inspect(payload)}")
    end
  end

  defp fuzz_ump(payload) do
    try do
      _result = GovernanceCore.Protocols.UMP.parse(payload)
      :ok
    rescue
      e ->
        Logger.error("UMP parser crashed on payload: #{inspect(payload)}, error: #{inspect(e)}")
    catch
      kind, reason ->
        Logger.error("UMP parser threw #{kind}: #{inspect(reason)} on payload: #{inspect(payload)}")
    end
  end
end
