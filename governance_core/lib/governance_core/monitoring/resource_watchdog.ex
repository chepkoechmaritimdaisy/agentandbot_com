defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  A GenServer that monitors agent container workloads (CPU and RAM) via Docker.
  Logs warnings if usage exceeds 80% to identify OOM kill risks.
  """
  use GenServer
  require Logger

  # Continuous interval: 5 minutes
  @interval 5 * 60 * 1000

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
    check_docker_stats()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check_resources, @interval)
  end

  def check_docker_stats do
    Logger.info("Resource Watchdog checking container stats...")

    try do
      case System.cmd("docker", ["stats", "--no-stream"]) do
        {output, 0} ->
          parse_and_check_stats(output)

        {error_output, exit_code} ->
          Logger.warning("Docker stats command failed with exit code #{exit_code}: #{error_output}")
      end
    rescue
      e in ErlangError ->
        Logger.error("Failed to execute docker stats (perhaps docker is not installed): #{inspect(e)}")
    end
  end

  defp parse_and_check_stats(output) do
    # Skip the header line
    lines = String.split(output, "\n", trim: true)

    if length(lines) > 1 do
      [_header | containers] = lines

      Enum.each(containers, fn line ->
        # Split by 2 or more spaces
        parts = String.split(line, ~r/\s{2,}/)

        if length(parts) >= 5 do
          container_id = Enum.at(parts, 0)
          cpu_str = Enum.at(parts, 2)
          mem_str = Enum.at(parts, 4)

          check_usage(container_id, "CPU", cpu_str)
          check_usage(container_id, "Memory", mem_str)
        end
      end)
    else
      Logger.info("No running containers found to monitor.")
    end
  end

  defp check_usage(container_id, type, usage_str) do
    # Parse string like "0.01%" or "85.5%"
    case Float.parse(String.trim_trailing(usage_str, "%")) do
      {usage, _} ->
        if usage > 80.0 do
          Logger.warning("Resource Watchdog Alert: Container #{container_id} is using #{usage}% #{type} (Exceeds 80% threshold). Risk of OOM kill / starvation.")
        end
      :error ->
        Logger.debug("Could not parse #{type} usage: #{usage_str} for container #{container_id}")
    end
  end
end
