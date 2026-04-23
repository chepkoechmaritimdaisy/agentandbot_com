defmodule GovernanceCore.ResourceWatchdog do
  @moduledoc """
  Monitors CPU and RAM usage for agents running on Docker Swarm or K3s.
  Identifies containers exceeding limits or at risk of OOM kill and logs/reports them.
  Uses real system calls where possible instead of randomized fake data.
  """
  use GenServer
  require Logger

  # 5 minutes in milliseconds
  @interval 5 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl GenServer
  def init(state) do
    # Safely check if docker binary is available
    if System.find_executable("docker") do
      schedule_check()
    else
      Logger.warning("ResourceWatchdog: Docker not found. Resource monitoring disabled to prevent errors.")
    end
    {:ok, state}
  end

  @impl GenServer
  def handle_info(:check, state) do
    perform_check()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check, @interval)
  end

  def perform_check do
    Logger.info("Starting Resource Watchdog check via Docker stats...")

    agents = get_running_agents()

    Enum.each(agents, fn agent ->
      if agent.ram_usage > 90.0 do
        Logger.error("Resource Watchdog: Agent #{agent.id} is at high risk of OOM kill! (RAM: #{agent.ram_usage}%)")
        report_violation(agent, :ram_oom_risk, agent.ram_usage)
      else
        if agent.cpu_usage > 95.0 do
          Logger.warning("Resource Watchdog: Agent #{agent.id} is exceeding CPU limits! (CPU: #{agent.cpu_usage}%)")
          report_violation(agent, :cpu_limit_exceeded, agent.cpu_usage)
        end
      end
    end)

    Logger.info("Resource Watchdog check completed.")
  end

  defp get_running_agents do
    # Attempt to query actual Docker stats
    case System.cmd("docker", ["stats", "--no-stream", "--format", "{{.Name}},{{.CPUPerc}},{{.MemPerc}}"]) do
      {output, 0} ->
        parse_docker_stats(output)
      {error_msg, _} ->
        Logger.error("ResourceWatchdog: Failed to read docker stats: #{error_msg}")
        []
    end
  end

  defp parse_docker_stats(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.map(fn line ->
      [name, cpu_str, mem_str] = String.split(line, ",")

      # Strip the '%' character and convert to float
      cpu = parse_percent(cpu_str)
      mem = parse_percent(mem_str)

      %{id: name, cpu_usage: cpu, ram_usage: mem}
    end)
  end

  defp parse_percent(str) do
    cleaned = String.replace(str, "%", "") |> String.trim()
    case Float.parse(cleaned) do
      {val, _} -> val
      :error -> 0.0
    end
  end

  defp report_violation(agent, violation_type, value) do
    # In a real system, this could save to the database, notify via Slack/Email, etc.
    Logger.info("Reporting violation for #{agent.id}: #{violation_type} at #{value}%")
  end
end
