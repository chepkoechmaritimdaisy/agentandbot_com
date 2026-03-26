defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  GenServer that monitors Docker Swarm/K3s agent container resource usage (CPU/RAM).
  Logs warnings for containers exceeding quotas or at risk of OOM.
  Gracefully handles missing docker executable and non-zero exit codes.
  """
  use GenServer
  require Logger

  # 5 minutes in milliseconds
  @interval 5 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_check()
    {:ok, state}
  end

  def handle_info(:check_resources, state) do
    check_docker_stats()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check_resources, @interval)
  end

  def check_docker_stats do
    Logger.debug("Running Resource Watchdog checks...")

    try do
      case System.cmd("docker", ["stats", "--no-stream", "--format", "{{.Name}},{{.CPUPerc}},{{.MemUsage}}"]) do
        {output, 0} ->
          parse_and_log_stats(output)

        {error_msg, exit_code} ->
          Logger.warning("docker stats returned non-zero exit code #{exit_code}: #{error_msg}")
      end
    rescue
      e in ErlangError ->
        Logger.error("Failed to execute docker stats (executable missing?): #{inspect(e)}")
    end
  end

  defp parse_and_log_stats(output) do
    # Expected format: container_name,5.4%,100MiB / 2GiB
    lines = String.split(output, "\n", trim: true)

    Enum.each(lines, fn line ->
      case String.split(line, ",") do
        [name, cpu, mem] ->
          check_limits(name, cpu, mem)

        _ ->
          Logger.warning("Resource Watchdog encountered unexpected docker stats format: #{line}")
      end
    end)
  end

  defp check_limits(name, cpu, mem) do
    cpu_value = parse_percentage(cpu)
    # This is a simplified check for memory usage percentage
    # A complete implementation might parse "100MiB / 2GiB" specifically
    # Here we just look at the first part and assume we want to alert on high absolute usage
    # or implement a more robust parser for the specific memory string.

    if cpu_value > 80.0 do
      Logger.warning("Resource Watchdog ALERT: Container #{name} CPU usage is high (#{cpu})")
    end

    # Simple heuristic for memory warning (e.g. if the string implies it's nearing limit)
    # Ideally, we calculate the percentage from the "used / limit" string.
    mem_usage_pct = parse_mem_percentage(mem)

    if mem_usage_pct > 85.0 do
      Logger.warning("Resource Watchdog ALERT: Container #{name} at risk of OOM (Memory: #{mem})")
    end
  end

  defp parse_percentage(pct_str) do
    pct_str
    |> String.replace("%", "")
    |> String.trim()
    |> Float.parse()
    |> case do
      {val, _} -> val
      :error -> 0.0
    end
  end

  defp parse_mem_percentage(mem_str) do
    # Example format: "1.2GiB / 2GiB"
    case String.split(mem_str, " / ") do
      [used_str, limit_str] ->
        used = parse_bytes(used_str)
        limit = parse_bytes(limit_str)

        if limit > 0 do
          (used / limit) * 100.0
        else
          0.0
        end

      _ ->
        0.0
    end
  end

  defp parse_bytes(str) do
    cond do
      String.ends_with?(str, "GiB") -> parse_num(str, "GiB") * 1024 * 1024 * 1024
      String.ends_with?(str, "MiB") -> parse_num(str, "MiB") * 1024 * 1024
      String.ends_with?(str, "KiB") -> parse_num(str, "KiB") * 1024
      String.ends_with?(str, "B") -> parse_num(str, "B")
      true -> 0.0
    end
  end

  defp parse_num(str, suffix) do
    str
    |> String.replace(suffix, "")
    |> String.trim()
    |> Float.parse()
    |> case do
      {val, _} -> val
      :error -> 0.0
    end
  end
end
