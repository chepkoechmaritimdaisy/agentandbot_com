defmodule GovernanceCore.ResourceWatchdog do
  @moduledoc """
  Monitors agents running on Docker Swarm or K3s for CPU and RAM usage.
  Logs warnings for containers exceeding quotas or at risk of OOM kills.
  """
  use GenServer
  require Logger

  # Check every 5 minutes
  @interval 5 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_check()
    {:ok, state}
  end

  def handle_info(:check_resources, state) do
    perform_check()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check_resources, @interval)
  end

  def perform_check do
    Logger.info("Starting Resource Watchdog check...")

    # In a real environment, this would call Docker/K8s APIs.
    # For simulation, we check for 'mock' high resource agents.
    agents = fetch_running_agents()

    Enum.each(agents, fn agent ->
      if agent.memory_usage > agent.memory_limit * 0.9 do
        Logger.warning("ResourceWatchdog: Agent #{agent.id} is at risk of OOM! Memory: #{agent.memory_usage}MB / #{agent.memory_limit}MB")
      end

      if agent.cpu_usage > agent.cpu_limit * 0.9 do
        Logger.warning("ResourceWatchdog: Agent #{agent.id} is exceeding CPU limits! CPU: #{agent.cpu_usage}% / #{agent.cpu_limit}%")
      end
    end)
  end

  defp fetch_running_agents do
    # Simulated agent data for demonstration purposes
    [
      %{id: "agent-1", memory_usage: 150, memory_limit: 512, cpu_usage: 10, cpu_limit: 100},
      %{id: "agent-2", memory_usage: 480, memory_limit: 512, cpu_usage: 95, cpu_limit: 100}, # High usage
      %{id: "agent-3", memory_usage: 200, memory_limit: 1024, cpu_usage: 50, cpu_limit: 100}
    ]
  end
end
