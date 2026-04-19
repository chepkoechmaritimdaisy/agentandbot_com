defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  A GenServer that monitors the CPU and RAM usage of containers
  using Docker stats. Logs warnings for containers exceeding
  expected usage or at risk of OOM.
  """

  use GenServer
  require Logger

  # 5 minutes in milliseconds
  @interval 5 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_check()
    {:ok, state}
  end

  def handle_info(:check, state) do
    perform_check()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check, @interval)
  end

  defp perform_check do
    Logger.debug("Starting Resource Watchdog check...")

    try do
      case System.cmd("docker", ["stats", "--no-stream"]) do
        {output, 0} ->
          analyze_stats(output)

        {_output, exit_code} ->
          Logger.error("Resource Watchdog: docker stats failed with exit code #{exit_code}")
      end
    rescue
      e in ErlangError ->
        Logger.warning("Resource Watchdog: Failed to run docker command (is docker installed?): #{inspect(e)}")
    end
  end

  defp analyze_stats(output) do
    lines = String.split(output, "\n", trim: true)
    Enum.each(lines, fn line ->
      # Example line: "container_id 0.50% 10MiB / 2GiB"
      Logger.info("Resource usage: #{line}")

      # Basic heuristic check based on string matching
      if String.contains?(line, "90.00%") or String.contains?(line, "99.") do
        Logger.warning("Resource Warning: High usage detected for #{line}")
      end
    end)
  end
end
