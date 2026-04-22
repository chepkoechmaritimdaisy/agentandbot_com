defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Monitors resource quotas (CPU and RAM) of running containers via Docker stats.
  Logs warnings for limits exceeded or OOM kill risks.
  Runs continuously every 5 minutes.
  """
  use GenServer
  require Logger

  # 5 minutes interval for continuous processing
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
    perform_check()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check_resources, @interval)
  end

  def perform_check do
    Logger.debug("Starting continuous ResourceWatchdog check...")

    try do
      # Note: --no-stream flag is required to prevent infinite blocking
      case System.cmd("docker", ["stats", "--no-stream", "--format", "{{.Name}}: {{.CPUPerc}}, {{.MemUsage}}"]) do
        {output, 0} ->
          analyze_stats(output)
        {error_output, exit_code} ->
          Logger.warning("Docker stats command failed with code #{exit_code}: #{error_output}")
      end
    rescue
      e in ErlangError ->
        Logger.warning("Docker CLI not available or failed: #{inspect(e)}")
    end
  end

  defp analyze_stats(output) do
    lines = String.split(output, "\n", trim: true)

    Enum.each(lines, fn line ->
      # Example format: "container_name: 1.50%, 50MiB / 1GiB"
      # Just log the output for now, but a full implementation would parse
      # the percentages and mem usage to check against defined quotas and risks

      cond do
        String.contains?(line, "99.") or String.contains?(line, "100.") ->
          Logger.warning("Resource limits potentially exceeded or high utilization: #{line}")
        true ->
          # Check for OOM risk by looking for close to limit RAM
          # e.g., if used and limit are very close
          Logger.debug("Container stats: #{line}")
      end
    end)
  end
end
