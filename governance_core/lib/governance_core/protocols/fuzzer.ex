defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Continuous Fuzzer for ClawSpeak and UMP protocols.
  Runs periodically to ensure parser stability against random binary inputs.
  """
  use GenServer
  require Logger

  alias GovernanceCore.Protocols.{ClawSpeak, UMP}

  @interval 60 * 1000 # 1 minute

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_fuzz()
    {:ok, state}
  end

  def handle_info(:fuzz, state) do
    fuzz_protocols()
    schedule_fuzz()
    {:noreply, state}
  end

  defp schedule_fuzz do
    Process.send_after(self(), :fuzz, @interval)
  end

  defp fuzz_protocols do
    Logger.debug("Starting fuzzing cycle for ClawSpeak and UMP...")

    # Generate 100 random binaries for fuzzing
    StreamData.binary()
    |> Enum.take(100)
    |> Enum.each(fn bin ->
      fuzz_clawspeak(bin)
      fuzz_ump(bin)
    end)
  end

  defp fuzz_clawspeak(bin) do
    try do
      ClawSpeak.decode(bin)
    rescue
      e ->
        Logger.error("ClawSpeak decoder crashed on input #{inspect(bin)}: #{inspect(e)}")
    catch
      kind, reason ->
        Logger.error("ClawSpeak decoder caught #{kind} on input #{inspect(bin)}: #{inspect(reason)}")
    end
  end

  defp fuzz_ump(bin) do
    try do
      UMP.parse(bin)
    rescue
      e ->
        Logger.error("UMP parser crashed on input #{inspect(bin)}: #{inspect(e)}")
    catch
      kind, reason ->
        Logger.error("UMP parser caught #{kind} on input #{inspect(bin)}: #{inspect(reason)}")
    end
  end
end
