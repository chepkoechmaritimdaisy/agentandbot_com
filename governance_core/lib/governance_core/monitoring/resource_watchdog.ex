defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  use GenServer
  require Logger

  @check_interval 30_000 # 30 seconds
  @memory_limit_mb 512
  @cpu_limit_percent 80

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    Logger.info("ResourceWatchdog started. Monitoring Docker/K8s metrics...")
    schedule_check()
    {:ok, state}
  end

  @impl true
  def handle_info(:check_resources, state) do
    check_metrics()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check_resources, @check_interval)
  end

  defp check_metrics do
    case Application.get_env(:governance_core, :resource_metrics_url) do
      nil ->
        Logger.debug("ResourceWatchdog: No metrics URL configured. Skipping check.")

      url ->
        metrics = fetch_metrics_from_url(url)

        Enum.each(metrics, fn {container, usage} ->
          analyze_usage(container, usage)
        end)
    end
  end

  defp fetch_metrics_from_url(url) do
    # In a real environment, this would call K8s Metrics API or Docker Stats
    # e.g., Req.get(url)
    # For now, return empty list unless implemented
    Logger.info("ResourceWatchdog: Fetching metrics from #{url} (Implementation Pending)")
    []
  end

  defp analyze_usage(container, %{memory_mb: mem, cpu_percent: cpu}) do
    if mem > @memory_limit_mb do
      Logger.warning("[OOM Risk] Container '#{container}' using #{mem}MB RAM (Limit: #{@memory_limit_mb}MB)")
    end

    if cpu > @cpu_limit_percent do
      Logger.warning("[CPU Alert] Container '#{container}' using #{cpu}% CPU")
    end
  end
end
