defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  GenServer that monitors Docker container CPU and RAM usage
  to identify agents exceeding limits or at risk of OOM kills.
  """
  use GenServer
  require Logger

  @interval 5 * 60 * 1000 # 5 minutes

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_check()
    {:ok, state}
  end

  @impl true
  def handle_info(:check_resources, state) do
    Logger.info("Checking Container Resources...")

    try do
      case System.cmd("docker", ["stats", "--no-stream"]) do
        {output, 0} ->
          process_stats(output)
        {error_output, exit_code} ->
          Logger.error("Docker stats failed with code #{exit_code}: #{error_output}")
      end
    rescue
      e in ErlangError ->
        Logger.error("Failed to execute docker command: #{inspect(e)}")
    end

    schedule_check()
    {:noreply, state}
  end

  defp process_stats(output) do
    lines = String.split(output, "\n", trim: true)

    # Skip header line, then log all containers. In a real scenario we would parse
    # CPUPerc and MemUsage and compare against thresholds. For now, we log the stats.
    Enum.each(Enum.drop(lines, 1), fn line ->
      Logger.warning("Container Resource Usage: #{line}")
    end)
  end

  defp schedule_check do
    Process.send_after(self(), :check_resources, @interval)
  end
end
