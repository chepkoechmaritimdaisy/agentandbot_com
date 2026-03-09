defmodule GovernanceCore.Fuzzer do
  @moduledoc """
  Periodically uses StreamData.binary() to fuzz UMP.Parser and ClawSpeak.
  Logs any crashes or inconsistent pattern matching errors.
  """
  use GenServer
  require Logger

  # Run every hour, adjust as needed
  @interval 60 * 60 * 1000

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

  def perform_fuzzing do
    Logger.info("Starting ClawSpeak (UMP) Fuzzing...")

    # Generate 1000 random binary payloads using StreamData
    StreamData.binary()
    |> Enum.take(1000)
    |> Enum.each(fn random_binary ->
      # 1. Fuzz ClawSpeak Parser
      try do
        GovernanceCore.Protocols.ClawSpeak.decode(random_binary)
      rescue
        e ->
          Logger.error("ClawSpeak decoder crashed on fuzz input: #{inspect(e)}\nInput: #{inspect(random_binary)}")
      catch
        kind, reason ->
          Logger.error("ClawSpeak decoder caught #{kind}: #{inspect(reason)}\nInput: #{inspect(random_binary)}")
      end

      # 2. Fuzz UMP Parser
      try do
        GovernanceCore.Protocols.UMP.Parser.parse_frame(random_binary)
      rescue
        e ->
          Logger.error("UMP Parser crashed on fuzz input: #{inspect(e)}\nInput: #{inspect(random_binary)}")
      catch
        kind, reason ->
          Logger.error("UMP Parser caught #{kind}: #{inspect(reason)}\nInput: #{inspect(random_binary)}")
      end
    end)

    Logger.info("Finished ClawSpeak (UMP) Fuzzing.")
  end
end
