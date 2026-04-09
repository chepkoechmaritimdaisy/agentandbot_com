defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Periodically monitors Docker containers using `docker stats` to ensure
  agent container resource limits (CPU/RAM) aren't being exceeded and
  logging warnings for OOM risks without writing to the filesystem.
  """
  use GenServer
  require Logger

  @interval 5 * 60 * 1000 # 5 minutes

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_check()
    {:ok, state}
  end

  def handle_info(:check, state) do
    perform_check()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check, @interval)
  end

  def perform_check do
    Logger.debug("Running ResourceWatchdog checks...")
    try do
      case System.cmd("docker", ["stats", "--no-stream", "--format", "{{.Name}}|{{.CPUPerc}}|{{.MemUsage}}"]) do
        {output, 0} ->
          analyze_stats(output)
        {output, status} ->
          Logger.warning("docker stats returned non-zero status #{status}: #{output}")
      end
    rescue
      e in ErlangError ->
        Logger.warning("Failed to run docker stats (docker might not be installed): #{inspect(e)}")
    end
  end

  defp analyze_stats(output) do
    lines = String.split(output, "\n", trim: true)

    Enum.each(lines, fn line ->
      case String.split(line, "|") do
        [name, cpu_str, mem_str] ->
          check_container(name, cpu_str, mem_str)
        _ ->
          Logger.debug("Malformed docker stats line: #{line}")
      end
    end)
  end

  defp check_container(name, cpu_str, mem_str) do
    # Simple heuristic checks

    # Strip '%' and check CPU
    cpu_val =
      case Float.parse(String.replace(cpu_str, "%", "")) do
        {val, _} -> val
        :error -> 0.0
      end

    if cpu_val > 90.0 do
      Logger.warning("ResourceWatchdog: Container #{name} CPU usage is high: #{cpu_val}%")
    end

    # Check memory for risk of OOM
    # For now, if usage > limit is high, we warn. The format is usually "100MiB / 200MiB"
    if String.contains?(mem_str, "/") do
      [used_str, limit_str] = String.split(mem_str, " / ")

      used = parse_memory(used_str)
      limit = parse_memory(limit_str)

      if limit > 0 and (used / limit) > 0.90 do
        Logger.warning("ResourceWatchdog: Container #{name} memory usage is near limit (#{Float.round(used / limit * 100, 2)}%) - OOM Risk!")
      end
    end
  end

  # Extremely simplified memory parsing (returns relative numbers)
  defp parse_memory(mem_str) do
    cond do
      String.contains?(mem_str, "GiB") ->
        {val, _} = Float.parse(mem_str)
        val * 1024
      String.contains?(mem_str, "MiB") ->
        {val, _} = Float.parse(mem_str)
        val
      String.contains?(mem_str, "KiB") ->
        {val, _} = Float.parse(mem_str)
        val / 1024
      String.contains?(mem_str, "B") ->
        {val, _} = Float.parse(mem_str)
        val / (1024 * 1024)
      true ->
        0.0
    end
  end
end
