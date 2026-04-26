defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Fuzzer and stress tester for ClawSpeak (UMP) protocol.
  Continuously tests the boundaries of the protocol with random binary data.
  """
  use GenServer
  require Logger
  alias GovernanceCore.Protocols.UMP.Parser

  # 5 minutes in milliseconds
  @interval 5 * 60 * 1000

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
    fuzz_parser()
    schedule_fuzz()
    {:noreply, state}
  end

  defp schedule_fuzz do
    Process.send_after(self(), :fuzz, @interval)
  end

  defp fuzz_parser do
    # Generate 10 random frames to fuzz the parser
    Enum.each(1..10, fn _ ->
      frame = :crypto.strong_rand_bytes(:rand.uniform(64))

      try do
        Parser.parse_frame(frame)
      rescue
        e in MatchError ->
          Logger.debug("Fuzzer caught MatchError: #{inspect(e)}")
        e in FunctionClauseError ->
          Logger.debug("Fuzzer caught FunctionClauseError: #{inspect(e)}")
        e in RuntimeError ->
          Logger.debug("Fuzzer caught RuntimeError: #{inspect(e)}")
      end
    end)
  end
end
