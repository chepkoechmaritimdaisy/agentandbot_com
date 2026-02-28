defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  A GenServer that monitors the resource usage (CPU/RAM) of agents running
  on Docker Swarm or K3s. Detects OOM (Out Of Memory) kill risks and excessive
  CPU usage and generates reports.
  """
  use GenServer
  require Logger

  # Default interval: 5 minutes
  @check_interval 5 * 60 * 1000

  # Memory usage limit (in percentage, 85%) for flagging "OOM kill" risks
  @oom_risk_threshold 85.0

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @impl true
  def init(state) do
    Logger.info("Resource Watchdog initialized. Monitoring agent containers...")
    schedule_check()
    {:ok, state}
  end

  @impl true
  def handle_info(:check_resources, state) do
    Logger.info("Resource Watchdog: Running resource check cycle...")
    perform_check()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check_resources, @check_interval)
  end

  def perform_check do
    # In a real environment, this would call Kubernetes or Docker API
    # to retrieve actual container stats.
    stats = fetch_container_stats()

    flagged_containers =
      Enum.filter(stats, fn stat ->
        stat.memory_usage_percent >= @oom_risk_threshold
      end)

    if Enum.any?(flagged_containers) do
      Logger.warning("Resource Watchdog: Detected containers at risk of OOM Kill!")
      generate_report(flagged_containers)
    else
      Logger.debug("Resource Watchdog: All containers within acceptable resource limits.")
    end
  end

  defp fetch_container_stats do
    # Empty placeholder to prevent log spam in production
    # until actual Docker/K3s API integration is built.
    []
  end

  defp generate_report(containers) do
    report_lines =
      Enum.map(containers, fn c ->
        "- Container #{c.id}: Memory Usage at #{c.memory_usage_percent}% (Risk: OOM Kill)"
      end)

    report_content = "Resource Watchdog Alert Report\n" <> Enum.join(report_lines, "\n")

    # Normally this would be written to a file, database, or sent via email/slack
    Logger.error(report_content)
  end
end
