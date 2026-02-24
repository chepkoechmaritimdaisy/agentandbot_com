defmodule GovernanceCore.ResourceWatchdog do
  @moduledoc """
  Monitors resource usage of agents running on the infrastructure (Docker/K3s).
  Simulates fetching metrics and alerts on high CPU/RAM usage.
  """
  use GenServer
  require Logger

  # Check every 30 seconds
  @interval 30_000

  # Quotas
  @cpu_limit_percent 80.0
  @ram_limit_mb 1024

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_check()
    {:ok, state}
  end

  def handle_info(:check_resources, state) do
    check_resources()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check_resources, @interval)
  end

  defp check_resources do
    # In a real scenario, this would query Docker API or K8s Metrics Server
    metrics = fetch_simulated_metrics()

    Enum.each(metrics, fn {container_id, usage} ->
      check_usage(container_id, usage)
    end)
  end

  defp check_usage(container_id, %{cpu: cpu, ram: ram}) do
    if cpu > @cpu_limit_percent do
      Logger.warning("[ResourceWatchdog] High CPU usage in container #{container_id}: #{cpu}% (Limit: #{@cpu_limit_percent}%)")
      # Prepare report / take action
    end

    if ram > @ram_limit_mb do
      Logger.warning("[ResourceWatchdog] High RAM usage in container #{container_id}: #{ram}MB (Limit: #{@ram_limit_mb}MB) - Risk of OOM Kill")
    end
  end

  defp fetch_simulated_metrics do
    # Returns a list of {container_id, %{cpu: float, ram: int}}
    # Simulate some random data
    [
      {"agent-worker-1", %{cpu: :rand.uniform() * 100, ram: :rand.uniform(1500)}},
      {"agent-worker-2", %{cpu: :rand.uniform() * 90, ram: :rand.uniform(800)}},
      {"agent-manager", %{cpu: :rand.uniform() * 50, ram: :rand.uniform(500)}}
    ]
  end
end
