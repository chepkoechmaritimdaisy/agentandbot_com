defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  A GenServer that monitors the resource utilization (CPU and RAM) of agents.
  Identifies agents that exceed quotas or are at risk of being "OOM killed".
  """
  use GenServer
  require Logger

  # 1 minute in milliseconds
  @interval 60 * 1000

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

    case System.cmd("docker", ["stats", "--no-stream", "--format", "{{.ID}}\t{{.MemUsage}}"]) do
      {output, 0} ->
        agents = parse_docker_stats(output)

        agents_at_risk = Enum.filter(agents, fn agent ->
          # If RAM usage is above 90% of quota, consider it an OOM risk
          agent.quota_ram > 0 and (agent.ram / agent.quota_ram) > 0.90
        end)

        if Enum.empty?(agents_at_risk) do
          Logger.info("Resource Watchdog Check Passed: All agents within quotas.")
        else
          Logger.error("Resource Watchdog Warning: OOM risk detected for agents: #{inspect(agents_at_risk)}")
          report_risks(agents_at_risk)
        end

      {error_msg, _code} ->
        Logger.warning("Resource Watchdog Check Failed: Could not execute 'docker stats'. #{error_msg}")
    end
  rescue
    e in ErlangError ->
      Logger.warning("Resource Watchdog encountered error running 'docker stats': #{inspect(e)}")
  end

  defp parse_docker_stats(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.map(fn line ->
      [id, mem_string] = String.split(line, "\t", parts: 2)
      [used, limit] = String.split(mem_string, " / ")

      %{
        id: id,
        ram: parse_mem_to_mb(used),
        quota_ram: parse_mem_to_mb(limit)
      }
    end)
  end

  defp parse_mem_to_mb(mem_str) do
    # Example format: "256MiB" or "1.5GiB"
    cond do
      String.ends_with?(mem_str, "GiB") ->
        {val, _} = Float.parse(mem_str)
        val * 1024.0
      String.ends_with?(mem_str, "MiB") ->
        {val, _} = Float.parse(mem_str)
        val
      String.ends_with?(mem_str, "kB") ->
        {val, _} = Float.parse(mem_str)
        val / 1024.0
      true ->
        0.0
    end
  end

  defp report_risks(risky_agents) do
    # Do not write to filesystem; output critically to logging system
    report_content = Enum.map_join(risky_agents, "\n", fn agent ->
      "- Agent #{agent.id} using #{agent.ram}MB of #{agent.quota_ram}MB quota."
    end)

    Logger.error("OOM Risk Report\n\n#{report_content}")
  end
end
