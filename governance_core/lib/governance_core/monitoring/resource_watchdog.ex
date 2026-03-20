defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  GenServer that monitors agent containers on Docker Swarm or K3s
  to ensure they do not exceed their CPU and RAM resource quotas,
  logging warnings for risk of 'OOM kill'.
  """
  use GenServer
  require Logger

  @interval 60_000 # Check every 60 seconds

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

  def perform_check do
    Logger.info("Resource Watchdog checking container stats...")

    try do
      case System.cmd("docker", ["stats", "--no-stream", "--format", "{{.Name}}: {{.CPUPerc}} | {{.MemUsage}}"]) do
        {output, 0} ->
          process_stats(output)
        {output, exit_code} ->
          Logger.warning("docker stats returned non-zero exit code (#{exit_code}): #{output}")
      end
    rescue
      e in ErlangError ->
        Logger.warning("Docker executable not found or failed to execute: #{inspect(e)}")
    end
  end

  defp process_stats(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.each(fn line ->
      # Example line: "agent-1: 15.00% | 500MiB / 1GiB"
      case String.split(line, ": ", parts: 2) do
        [container_name, stats] ->
          Logger.info("Resource Watchdog stats for #{container_name} - #{stats}")
          # In a real implementation we would parse CPU % and memory limits here
          # and log an OOM warning if memory usage is approaching the limit.
          if String.contains?(stats, "95.") or String.contains?(stats, "99.") do
            Logger.warning("Container #{container_name} is nearing resource limit! Risk of OOM kill.")
          end
        _ ->
          Logger.debug("Unparseable docker stats line: #{line}")
      end
    end)
  end
end
