defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Monitors Docker container CPU and RAM usage dynamically via System.cmd("docker", ["stats"]).
  Logs warnings for high usage indicating potential OOM kills.
  Handles missing docker executables gracefully.
  """
  use GenServer
  require Logger

  @interval 5 * 60 * 1000 # 5 minutes

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    Logger.info("Starting Resource Watchdog...")
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
    try do
      # Run docker stats without stream to get a single snapshot
      case System.cmd("docker", ["stats", "--no-stream", "--format", "{{.Name}},{{.CPUPerc}},{{.MemUsage}}"]) do
        {output, 0} ->
          process_stats(output)
        {output, _code} ->
          Logger.warning("Docker stats command failed: #{output}")
      end
    rescue
      e in ErlangError ->
        Logger.warning("Docker executable not found or failed to execute: #{inspect(e)}")
    end
  end

  defp process_stats(output) do
    lines = String.split(output, "\n", trim: true)

    Enum.each(lines, fn line ->
      # Example format: container_name,0.01%,10MiB / 2GiB
      case String.split(line, ",") do
        [name, cpu, mem] ->
          check_limits(name, cpu, mem)
        _ ->
          :ok
      end
    end)
  end

  defp check_limits(name, cpu, mem) do
    # Simple check for CPU > 80% or Mem containing GB/GiB near limits
    cpu_val = parse_percentage(cpu)
    mem_percent = parse_mem_percentage(mem)

    if cpu_val > 80.0 do
      Logger.warning("[Resource Watchdog] High CPU Usage! Container: #{name}, CPU: #{cpu}")
    end

    if mem_percent > 80.0 do
      Logger.warning("[Resource Watchdog] High RAM Usage / OOM Risk! Container: #{name}, Memory: #{mem}")
    end
  end

  defp parse_percentage(str) do
    clean = String.replace(str, "%", "") |> String.trim()
    case Float.parse(clean) do
      {val, _} -> val
      :error ->
        case Integer.parse(clean) do
          {val, _} -> val * 1.0
          :error -> 0.0
        end
    end
  end

  defp parse_mem_percentage(str) do
    # Format typically: "10MiB / 2GiB"
    case String.split(str, "/") do
      [used, limit] ->
        used_mb = parse_to_mb(used)
        limit_mb = parse_to_mb(limit)
        if limit_mb > 0 do
          (used_mb / limit_mb) * 100.0
        else
          0.0
        end
      _ -> 0.0
    end
  end

  defp parse_to_mb(str) do
    clean = String.trim(str)
    cond do
      String.ends_with?(clean, "GiB") or String.ends_with?(clean, "GB") ->
        extract_val(clean) * 1024.0
      String.ends_with?(clean, "MiB") or String.ends_with?(clean, "MB") ->
        extract_val(clean)
      String.ends_with?(clean, "KiB") or String.ends_with?(clean, "KB") ->
        extract_val(clean) / 1024.0
      true ->
        extract_val(clean)
    end
  end

  defp extract_val(str) do
    num_str = Regex.replace(~r/[a-zA-Z ]/, str, "")
    case Float.parse(num_str) do
      {val, _} -> val
      :error ->
        case Integer.parse(num_str) do
          {val, _} -> val * 1.0
          :error -> 0.0
        end
    end
  end
end
