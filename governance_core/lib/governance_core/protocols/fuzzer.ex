defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  A background fuzzer process that periodically sends random binary data
  to the UMP Parser to detect crashes and ensure stability.
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
    perform_fuzz()
    schedule_fuzz()
    {:noreply, state}
  end

  defp schedule_fuzz do
    Process.send_after(self(), :fuzz, @interval)
  end

  defp perform_fuzz do
    # Generate 10 random binary chunks using stream_data
    StreamData.binary()
    |> Enum.take(10)
    |> Enum.each(fn bin ->
      try do
        Parser.parse_frame(bin)
      rescue
        e in [MatchError, FunctionClauseError, RuntimeError, ArgumentError] ->
          Logger.error("Fuzzer found a crash! Data: #{inspect(bin)}, Error: #{inspect(e)}")
      end
    end)
  end
end
