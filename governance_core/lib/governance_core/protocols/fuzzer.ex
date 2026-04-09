defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  A GenServer that periodically fuzzes ClawSpeak and UMP protocols.
  """
  use GenServer
  require Logger
  alias GovernanceCore.Protocols.{ClawSpeak, UMP}

  # 5 minutes in milliseconds
  @interval 5 * 60 * 1000
  @fuzz_count 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_fuzzing()
    {:ok, state}
  end

  def handle_info(:fuzz, state) do
    perform_fuzzing()
    schedule_fuzzing()
    {:noreply, state}
  end

  defp schedule_fuzzing do
    Process.send_after(self(), :fuzz, @interval)
  end

  defp perform_fuzzing do
    Logger.info("Starting periodic fuzzing of ClawSpeak and UMP protocols...")

    # Fuzz ClawSpeak
    binary_generator = StreamData.binary()

    Enum.each(Enum.take(binary_generator, @fuzz_count), fn payload ->
      try do
        ClawSpeak.decode(payload)
      rescue
        e ->
          Logger.error("ClawSpeak decoder crashed on payload: #{inspect(payload, limit: :infinity)}\nException: #{inspect(e)}")
      catch
        kind, reason ->
          Logger.error("ClawSpeak decoder caught #{kind} on payload: #{inspect(payload, limit: :infinity)}\nReason: #{inspect(reason)}")
      end
    end)

    # Fuzz UMP
    Enum.each(Enum.take(binary_generator, @fuzz_count), fn payload ->
      try do
        UMP.parse(payload)
      rescue
        e ->
          Logger.error("UMP parser crashed on payload: #{inspect(payload, limit: :infinity)}\nException: #{inspect(e)}")
      catch
        kind, reason ->
          Logger.error("UMP parser caught #{kind} on payload: #{inspect(payload, limit: :infinity)}\nReason: #{inspect(reason)}")
      end
    end)

    Logger.info("Fuzzing cycle complete.")
  end
end
