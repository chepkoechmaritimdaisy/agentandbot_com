defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  A GenServer that monitors the CPU and RAM usage of containers (Docker Swarm or K3s)
  running agent workloads. Reports warnings if limits are exceeded.
  """
  use GenServer
  require Logger

  # Run every 5 minutes
  @interval 5 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
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
      # Run docker stats to get current resource usage once (no stream)
      case System.cmd("docker", ["stats", "--no-stream", "--format", "{{.Name}}: {{.CPUPerc}} CPU, {{.MemUsage}} RAM"]) do
        {output, 0} ->
          analyze_stats(output)
        {error_msg, _} ->
          Logger.warning("Failed to run docker stats: #{error_msg}")
      end
    rescue
      e in ErlangError ->
        Logger.warning("Docker executable not found or failed to execute: #{inspect(e)}")
    end
  end

  defp analyze_stats(output) do
    lines = String.split(output, "\n", trim: true)

    Enum.each(lines, fn line ->
      # Simple log for now, can be extended with threshold matching
      Logger.info("Resource Watchdog Report: #{line}")

      # Example logic for OOM kill risk warning
      if String.contains?(line, "99.") or String.contains?(line, "100.") do
         Logger.warning("🚨 HIGH RESOURCE USAGE DETECTED: #{line} - Potential OOM Risk!")
      end
    end)
  end
end
