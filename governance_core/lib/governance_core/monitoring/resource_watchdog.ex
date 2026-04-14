defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Monitors CPU and RAM usage of containers running on Docker Swarm / K3s.
  Logs warnings for containers exceeding resource quotas or at risk of OOM kill.
  """
  use GenServer
  require Logger

  # 5 minutes in ms
  @interval 5 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_watch()
    {:ok, state}
  end

  @impl true
  def handle_info(:watch, state) do
    perform_watch()
    schedule_watch()
    {:noreply, state}
  end

  defp schedule_watch do
    Process.send_after(self(), :watch, @interval)
  end

  defp perform_watch do
    Logger.info("Starting Resource Watchdog...")

    try do
      case System.cmd("docker", ["stats", "--no-stream", "--format", "{{.Name}} {{.CPUPerc}} {{.MemUsage}}"]) do
        {output, 0} ->
          analyze_stats(output)
        {output, code} ->
          Logger.warning("Docker stats command failed with code #{code}: #{output}")
      end
    rescue
      e in ErlangError ->
        Logger.error("Failed to execute docker command (is docker installed?): #{inspect(e)}")
    end
  end

  defp analyze_stats(output) do
    lines = String.split(String.trim(output), "\n", trim: true)

    Enum.each(lines, fn line ->
      # Example line: "container_name 0.05% 10MiB / 2GiB"
      case String.split(line, " ", parts: 3) do
        [name, cpu, mem_info] ->
          check_cpu(name, cpu)
          check_mem(name, mem_info)
        _ ->
          :ok
      end
    end)
  end

  defp check_cpu(name, cpu) do
    cpu_value =
      cpu
      |> String.replace("%", "")
      |> Float.parse()

    case cpu_value do
      {val, _} when val > 80.0 ->
        Logger.warning("Container #{name} has high CPU usage: #{cpu}")
      _ ->
        :ok
    end
  end

  defp check_mem(name, mem_info) do
    # Simple heuristic: if it contains a large percentage or ratio, we could warn.
    # For now, we just log memory usage if it exceeds certain text heuristics
    # (A full implementation would parse MiB/GiB and compare against quotas).
    if String.contains?(mem_info, "GiB") do
      Logger.warning("Container #{name} is using a high amount of memory (GiB level): #{mem_info} - Risk of OOM kill")
    end
  end
end
