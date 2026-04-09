defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  A GenServer that monitors container CPU and RAM usage via `docker stats`.
  Gracefully handles missing `docker` executable or non-zero exit codes.
  Logs warnings if limits are exceeded.
  """
  use GenServer
  require Logger

  # Run every 5 minutes
  @interval 5 * 60 * 1000

  # Example thresholds
  @cpu_threshold_perc 80.0
  @mem_threshold_mb 500.0

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_check()
    {:ok, state}
  end

  def handle_info(:check, state) do
    Task.start(fn -> perform_check() end)
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check, @interval)
  end

  def perform_check do
    Logger.info("Starting Resource Watchdog check...")

    try do
      case System.cmd("docker", ["stats", "--no-stream", "--format", "{{.Name}} {{.CPUPerc}} {{.MemUsage}}"]) do
        {output, 0} ->
          process_stats(output)

        {_output, code} ->
          Logger.warning("docker stats returned non-zero exit code: #{code}. Docker might not be fully available.")
      end
    rescue
      e in ErlangError ->
        Logger.warning("Failed to execute docker stats. Executable might be missing. Exception: #{inspect(e)}")
    end
  end

  defp process_stats(output) do
    lines = String.split(output, "\n", trim: true)

    Enum.each(lines, fn line ->
      # Example format: "container_name 0.50% 50MiB / 2GiB"
      parts = String.split(line, " ", parts: 4)

      if length(parts) >= 3 do
        [name, cpu_str, mem_str | _] = parts

        cpu = parse_cpu(cpu_str)
        mem_mb = parse_mem(mem_str)

        if cpu > @cpu_threshold_perc do
          Logger.warning("Container #{name} CPU usage is high: #{cpu}% (Threshold: #{@cpu_threshold_perc}%)")
        end

        if mem_mb > @mem_threshold_mb do
          Logger.warning("Container #{name} memory usage is high: #{mem_mb}MiB (Threshold: #{@mem_threshold_mb}MiB) - Potential OOM Kill risk!")
        end
      end
    end)
  end

  defp parse_cpu(cpu_str) do
    # Remove "%" and parse to float
    clean_str = String.replace(cpu_str, "%", "")
    case Float.parse(clean_str) do
      {val, _} -> val
      :error -> 0.0
    end
  end

  defp parse_mem(mem_str) do
    # Simple parser for MiB/GiB/etc.
    cond do
      String.ends_with?(mem_str, "GiB") ->
        val = String.replace(mem_str, "GiB", "") |> String.trim() |> Float.parse() |> elem(0)
        val * 1024
      String.ends_with?(mem_str, "MiB") ->
        String.replace(mem_str, "MiB", "") |> String.trim() |> Float.parse() |> elem(0)
      String.ends_with?(mem_str, "KiB") ->
        val = String.replace(mem_str, "KiB", "") |> String.trim() |> Float.parse() |> elem(0)
        val / 1024
      true ->
        0.0
    end
  rescue
    _ -> 0.0
  end
end
