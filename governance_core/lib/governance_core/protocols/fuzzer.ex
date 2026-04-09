defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Periodically fuzzes the UMP Parser to detect inconsistent pattern matching.
  Uses StreamData to generate random binary frames.
  """
  use GenServer
  require Logger

  # Run fuzzer every 1 minute
  @interval 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_fuzz()
    {:ok, state}
  end

  def handle_info(:fuzz, state) do
    perform_fuzz()
    schedule_fuzz()
    {:noreply, state}
  end

  defp schedule_fuzz do
    Process.send_after(self(), :fuzz, @interval)
  end

  defp perform_fuzz do
    Logger.info("Starting UMP Protocol Fuzzing pass...")
    # Generate random binaries to fuzz the parser
    # We use StreamData.binary() and take a few samples
    StreamData.binary()
    |> Enum.take(100)
    |> Enum.each(fn bin ->
      try do
        # We don't care about the result, just that it doesn't crash the VM
        GovernanceCore.Protocols.UMP.Parser.parse_frame(bin)
      rescue
        e -> Logger.error("Fuzzer crash on input #{inspect(bin)}: #{inspect(e)}")
      catch
        type, value -> Logger.error("Fuzzer catch on input #{inspect(bin)}: #{inspect(type)} #{inspect(value)}")
      end
    end)
    Logger.info("UMP Protocol Fuzzing pass completed.")
  end
end
