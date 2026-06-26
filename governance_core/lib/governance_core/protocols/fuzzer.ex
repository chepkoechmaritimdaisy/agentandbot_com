defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  GenServer that loops on a timer to fuzz the GovernanceCore.Protocols.UMP.parse/1
  with random binaries. Ensures protocol resilience without crashing the main application.
  """
  use GenServer
  require Logger

  # Default to 5 seconds
  @interval 5_000

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

  defp perform_fuzz do
    Logger.debug("Running UMP Fuzzer iteration...")

    # Generate random binary data to test UMP parser
    random_binary =
      StreamData.binary()
      |> Enum.take(1)
      |> List.first()

    try do
      # We test whether the parser can handle arbitrary binary input without crashing
      GovernanceCore.Protocols.UMP.parse(random_binary)
    rescue
      e in [MatchError, FunctionClauseError, RuntimeError, ArgumentError] ->
        Logger.error("Fuzzer caught exception in UMP.parse/1: #{inspect(e)}")
    end
  end
end
