defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Monitors CPU and RAM usage of containers via Docker stats.
  """
  use GenServer
  require Logger

  @interval 5 * 60 * 1000 # 5 minutes

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_watchdog()
    {:ok, state}
  end

  @impl true
  def handle_info(:watch, state) do
    check_resources()
    schedule_watchdog()
    {:noreply, state}
  end

  defp schedule_watchdog do
    Process.send_after(self(), :watch, @interval)
  end

  defp check_resources do
    try do
      case System.cmd("docker", ["stats", "--no-stream", "--format", "{{.Container}} {{.CPUPerc}} {{.MemUsage}}"]) do
        {output, 0} ->
          parse_and_alert(output)
        {error_output, exit_code} ->
          Logger.warning("Docker stats failed with code #{exit_code}: #{error_output}")
      end
    rescue
      # Handle systems without Docker installed gracefully
      e in ErlangError ->
        Logger.warning("Docker executable not found or failed to execute: #{inspect(e)}")
    end
  end

  defp parse_and_alert(output) do
    lines = String.split(output, "\n", trim: true)

    for line <- lines do
      [container, cpu, mem | _] = String.split(line, " ", parts: 3)

      # CPU percentage could be "50.50%", parse it out
      cpu_val = parse_percentage(cpu)

      # Check for high CPU
      if cpu_val > 90.0 do
        Logger.warning("High CPU Alert! Container #{container} is at #{cpu} CPU")
      end

      # Check for High RAM (OOM risk) - simplistic check based on GB or 90%
      # In reality, MemUsage looks like "20MiB / 1GiB"
      if is_oom_risk?(mem) do
        Logger.warning("OOM Risk Alert! Container #{container} memory usage is high: #{mem}")
      end
    end
  end

  defp parse_percentage(str) do
    str = String.replace(str, "%", "")
    case Float.parse(str) do
      {val, _} -> val
      :error -> 0.0
    end
  end

  defp is_oom_risk?(mem_str) do
    # Expected format: "500MiB / 1GiB"
    case String.split(mem_str, " / ") do
      [used, total] ->
        used_mb = parse_memory_to_mb(used)
        total_mb = parse_memory_to_mb(total)

        if total_mb > 0 do
          (used_mb / total_mb) > 0.90
        else
          false
        end
      _ -> false
    end
  end

  defp parse_memory_to_mb(str) do
    str = String.trim(str)

    cond do
      String.ends_with?(str, "GiB") ->
        {val, _} = Float.parse(String.replace(str, "GiB", ""))
        val * 1024
      String.ends_with?(str, "MiB") ->
        {val, _} = Float.parse(String.replace(str, "MiB", ""))
        val
      String.ends_with?(str, "KiB") ->
        {val, _} = Float.parse(String.replace(str, "KiB", ""))
        val / 1024
      String.ends_with?(str, "B") ->
        {val, _} = Float.parse(String.replace(str, "B", ""))
        val / (1024 * 1024)
      true ->
        0.0
    end
  rescue
    _ -> 0.0
  end
end
