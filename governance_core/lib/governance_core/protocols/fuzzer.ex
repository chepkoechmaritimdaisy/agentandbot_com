defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  A GenServer that continuously tests ClawSpeak / UMP parsers with random binary payloads
  generated via StreamData to identify potential matching failures and edge cases.
  """
  use GenServer
  require Logger

  # Default interval for fuzzing iteration
  @interval 1000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    schedule_fuzz()
    {:ok, %{}}
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
    try do
      # Generate random binary data
      payload =
        StreamData.binary()
        |> Enum.take(1)
        |> hd()

      # Attempt to parse as ClawSpeak
      case GovernanceCore.Protocols.ClawSpeak.decode(payload) do
        {:ok, _, _} -> :ok
        {:error, _} -> :ok
      end

      # Attempt to parse as UMP
      case GovernanceCore.Protocols.UMP.parse(payload) do
        {:ok, _} -> :ok
        {:error, _} -> :ok
      end
    rescue
      e in [MatchError, FunctionClauseError, RuntimeError, ArgumentError] ->
        Logger.error("Fuzzer encountered exception: #{inspect(e)}")
    end
  end
end
