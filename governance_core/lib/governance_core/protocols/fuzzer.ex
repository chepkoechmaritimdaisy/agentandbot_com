defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  A GenServer that fuzz tests the `GovernanceCore.Protocols.UMP.Parser` continuously.
  It generates random binary payloads using StreamData and tests parsing logic,
  catching specific errors without crashing the GenServer.
  """
  use GenServer
  require Logger

  @interval 5 * 60 * 1000 # 5 minutes

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
    Logger.info("Starting continuous fuzzing of UMP Parser...")

    generator = StreamData.binary()
    payloads = Enum.take(generator, 100) # Test 100 random payloads

    Enum.each(payloads, fn payload ->
      try do
        GovernanceCore.Protocols.UMP.Parser.parse_frame(payload)
      rescue
        e in [MatchError, FunctionClauseError, RuntimeError, ArgumentError] ->
          Logger.error("UMP Parser Fuzzing found a crash: #{Exception.format(:error, e, __STACKTRACE__)}")
      end
    end)

    Logger.info("Finished UMP Parser fuzzing iteration.")
  end
end
