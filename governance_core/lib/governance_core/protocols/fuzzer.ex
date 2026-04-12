defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  A background fuzzer that continuously feeds random binary data into the UMP Parser
  to detect protocol boundary vulnerabilities or missing edge cases without user intervention.
  """
  use GenServer
  require Logger

  # 5 seconds interval
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
    perform_fuzzing()
    schedule_fuzz()
    {:noreply, state}
  end

  defp schedule_fuzz do
    Process.send_after(self(), :fuzz, @interval)
  end

  defp perform_fuzzing do
    # Generate random binary data using StreamData generator
    generator = StreamData.binary()

    # Take a sample of binary inputs
    inputs = Enum.take(generator, 100)

    Enum.each(inputs, fn payload ->
      try do
        _result = GovernanceCore.Protocols.UMP.Parser.parse_frame(payload)
        # Even if it returns {:error, _}, that's fine as long as it doesn't crash the process
      rescue
        e ->
          Logger.error("Fuzzer Rescue: UMP Parser failed on input #{inspect(payload)}. Error: #{inspect(e)}")
      catch
        kind, reason ->
          Logger.error("Fuzzer Catch: UMP Parser caught #{kind} on input #{inspect(payload)}. Reason: #{inspect(reason)}")
      end
    end)
  end
end
