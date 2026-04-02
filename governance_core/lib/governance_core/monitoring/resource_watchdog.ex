defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Monitors Docker container resource usage (CPU/RAM).
  Logs warnings for limits exceeding thresholds.
  """
  use GenServer
  require Logger

  @interval 60 * 1000 # 1 minute

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    Logger.info("Starting Resource Watchdog...")
    schedule_check()
    {:ok, state}
  end

  def handle_info(:check, state) do
    check_resources()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check, @interval)
  end

  defp check_resources do
    try do
      case System.cmd("docker", ["stats", "--no-stream", "--format", "{{.Name}}: {{.CPUPerc}} CPU, {{.MemUsage}} RAM"]) do
        {output, 0} ->
          process_stats(output)
        {output, status} ->
          Logger.warning("Docker stats command failed with status #{status}: #{output}")
      end
    rescue
      e in ErlangError ->
        Logger.warning("Failed to execute docker command (executable may be missing): #{inspect(e)}")
    end
  end

  defp process_stats(output) do
    lines = String.split(output, "\n", trim: true)
    Enum.each(lines, fn line ->
      # Example logic: if a container uses > 80% CPU or has 'OOM' risk, log it.
      # Since we just want basic tracking, we will log everything or parse it simply.
      Logger.info("[ResourceWatchdog] Container Stat: #{line}")

      # Basic check to see if CPU >= 80%, including values over 100%
      if String.match?(line, ~r/([8-9][0-9]\.|[1-9][0-9]{2,}\.)[0-9]+% CPU/) do
        Logger.warning("[ResourceWatchdog] High CPU Usage detected: #{line}")
      end
    end)
  end
end
