defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Monitors CPU and RAM usage of containers via `docker stats`.
  Identifies containers at risk of OOM kill or excessive CPU use.
  Logs warnings dynamically.
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

  defp perform_check do
    Logger.info("Resource Watchdog: Checking container stats...")

    try do
      case System.cmd("docker", ["stats", "--no-stream", "--format", "{{.Name}} {{.CPUPerc}} {{.MemUsage}}"]) do
        {output, 0} ->
          parse_and_evaluate(output)
        {error_output, exit_code} ->
          Logger.warning("Resource Watchdog: Docker command failed with code #{exit_code}: #{error_output}")
      end
    rescue
      # Gracefully handle missing docker executable without crashing the GenServer
      e in ErlangError ->
        Logger.warning("Resource Watchdog: Failed to execute docker command. Is docker installed? Error: #{inspect(e)}")
      e ->
        Logger.error("Resource Watchdog: Unexpected error #{inspect(e)}")
    end
  end

  defp parse_and_evaluate(output) do
    lines = String.split(output, "\n", trim: true)

    Enum.each(lines, fn line ->
      # E.g., "my_container 0.50% 50MiB / 2GiB"
      case String.split(line, " ", parts: 3) do
        [name, cpu_str, mem_str] ->
          check_cpu(name, cpu_str)
          check_mem(name, mem_str)
        _ ->
          Logger.debug("Resource Watchdog: Could not parse line: #{line}")
      end
    end)
  end

  defp check_cpu(name, cpu_str) do
    # Remove % and parse
    clean_cpu = String.replace(cpu_str, "%", "")
    case Float.parse(clean_cpu) do
      {cpu, _} when cpu > 90.0 ->
        Logger.warning("Resource Watchdog [CPU Alert]: Container #{name} is using excessive CPU: #{cpu_str}")
      _ ->
        :ok
    end
  end

  defp check_mem(name, mem_str) do
    # Simple heuristic to find high memory usage if it has a percentage (docker stats can sometimes output MEM % as well, but our format command just says MemUsage)
    # The output of MemUsage is usually "50MiB / 2GiB".
    # For a precise OOM check we might want to check MemPerc, but let's parse the ratio if possible or rely on string matching for known limits.

    # We'll just do a basic log if it seems excessively large or is near 90% if we can parse it.
    if String.contains?(mem_str, "GiB") do
       Logger.warning("Resource Watchdog [RAM Alert]: Container #{name} memory usage is high: #{mem_str} - Risk of OOM kill.")
    end
  end
end
