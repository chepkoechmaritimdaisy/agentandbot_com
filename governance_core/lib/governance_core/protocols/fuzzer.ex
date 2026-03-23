defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Periodically fuzzes ClawSpeak and UMP protocols.
  """
  use GenServer
  require Logger

  @interval 60_000 # Run fuzzing every minute

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_fuzzing()
    {:ok, state}
  end

  @impl true
  def handle_info(:fuzz, state) do
    run_fuzz_tests()
    schedule_fuzzing()
    {:noreply, state}
  end

  defp schedule_fuzzing do
    Process.send_after(self(), :fuzz, @interval)
  end

  defp run_fuzz_tests do
    Logger.info("Running Fuzz Tests for ClawSpeak & UMP")

    binaries = StreamData.binary() |> Enum.take(100)

    for bin <- binaries do
      try do
        GovernanceCore.Protocols.ClawSpeak.decode(bin)
      rescue
        e -> Logger.warning("Fuzzing crashed ClawSpeak decode/1: #{inspect(e)}")
      catch
        e -> Logger.warning("Fuzzing caught throw in ClawSpeak decode/1: #{inspect(e)}")
      end

      try do
        GovernanceCore.Protocols.UMP.Parser.parse_frame(bin)
      rescue
        e -> Logger.warning("Fuzzing crashed UMP parse_frame/1: #{inspect(e)}")
      catch
        e -> Logger.warning("Fuzzing caught throw in UMP parse_frame/1: #{inspect(e)}")
      end
    end
  end
end
