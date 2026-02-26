defmodule GovernanceCore.ResourceWatchdog do
  @moduledoc """
  Monitors resource usage (CPU, RAM) of agents running on the platform.
  Enforces ResourceQuotas and detects potential OOM kills.
  """
  use GenServer
  require Logger

  # Check every minute
  @interval 60 * 1000

  # Memory limit in MB
  @memory_limit_mb 512
  # CPU warning threshold (percentage)
  @cpu_warning_threshold 80.0

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    Logger.info("Resource Watchdog started.")
    schedule_check()
    {:ok, state}
  end

  def handle_info(:check_resources, state) do
    check_quotas()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check_resources, @interval)
  end

  defp check_quotas do
    # In a real environment, this would query Docker Swarm or K3s metrics API.
    # Here we simulate the check.

    # Mock data for running agents
    agents_metrics = get_mock_metrics()

    Enum.each(agents_metrics, fn {agent_id, metrics} ->
      analyze_metrics(agent_id, metrics)
    end)
  end

  defp analyze_metrics(agent_id, %{memory_mb: mem, cpu_percent: cpu}) do
    if mem > @memory_limit_mb do
      Logger.warning("ResourceWatchdog: Agent #{agent_id} exceeded memory limit! Usage: #{mem}MB. Risk of OOM Kill.")
      # Trigger mitigation (e.g., restart, scale up)
    end

    if cpu > @cpu_warning_threshold do
      Logger.warning("ResourceWatchdog: Agent #{agent_id} high CPU usage: #{cpu}%.")
    end
  end

  defp get_mock_metrics do
    # Simulate some agents with varying usage
    %{
      "research-pro" => %{memory_mb: 120, cpu_percent: 15.5},
      "invoice-agent" => %{memory_mb: 450, cpu_percent: 60.0}, # Approaching limit
      "rogue-agent" => %{memory_mb: 600, cpu_percent: 95.0},   # Exceeding limit
      "sap-agent" => %{memory_mb: 800, cpu_percent: 40.0}      # Exceeding default limit, maybe authorized?
    }
  end
end
