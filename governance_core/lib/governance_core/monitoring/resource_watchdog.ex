defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Periodically monitors Docker container CPU and RAM usage.
  Logs warnings for containers exceeding resource quotas.
  """
  use GenServer
  require Logger

  # 5 minutes in milliseconds
  @interval 5 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_monitoring()
    {:ok, state}
  end

  def handle_info(:monitor, state) do
    perform_monitoring()
    schedule_monitoring()
    {:noreply, state}
  end

  defp schedule_monitoring do
    Process.send_after(self(), :monitor, @interval)
  end

  def perform_monitoring do
    Logger.debug("Starting Resource Watchdog Docker stats check...")

    try do
      case System.cmd("docker", ["stats", "--no-stream", "--format", "{{.Name}},{{.CPUPerc}},{{.MemUsage}}"]) do
        {output, 0} ->
          process_stats(output)
        {error, code} ->
          Logger.warning("Resource Watchdog failed to get docker stats: exit code #{code}: #{error}")
      end
    rescue
      e in ErlangError ->
        Logger.warning("Resource Watchdog missing docker command: #{inspect(e)}")
    end
  end

  defp process_stats(output) do
    lines = String.split(output, "\n", trim: true)

    Enum.each(lines, fn line ->
      [name, cpu_str, mem_str] = String.split(line, ",")

      # Parse CPU percentage (e.g., "0.01%")
      cpu_perc = String.replace(cpu_str, "%", "") |> Float.parse()

      # Parse memory usage string (e.g., "1.23MiB / 1GiB")
      mem_usage_parts = String.split(mem_str, " / ")
      mem_usage_val = parse_mem(List.first(mem_usage_parts) || "0B")

      case cpu_perc do
        {cpu, _} when cpu > 80.0 ->
          Logger.warning("Resource Watchdog: Container #{name} CPU usage high: #{cpu}%")
        _ -> :ok
      end

      # 1GB threshold in bytes
      if mem_usage_val > 1_073_741_824 do
        Logger.warning("Resource Watchdog: Container #{name} Memory usage high: #{mem_usage_val} bytes")
      end
    end)
  end

  defp parse_mem(mem_str) do
    cond do
      String.ends_with?(mem_str, "GiB") ->
        {val, _} = Float.parse(String.replace(mem_str, "GiB", ""))
        trunc(val * 1024 * 1024 * 1024)
      String.ends_with?(mem_str, "MiB") ->
        {val, _} = Float.parse(String.replace(mem_str, "MiB", ""))
        trunc(val * 1024 * 1024)
      String.ends_with?(mem_str, "KiB") ->
        {val, _} = Float.parse(String.replace(mem_str, "KiB", ""))
        trunc(val * 1024)
      String.ends_with?(mem_str, "B") ->
        {val, _} = Float.parse(String.replace(mem_str, "B", ""))
        trunc(val)
      true -> 0
    end
  end
end
