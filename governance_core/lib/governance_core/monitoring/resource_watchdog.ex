defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Periodically monitors Docker containers' CPU and RAM using `docker stats`.
  Handles missing docker via ErlangError rescue and logs warnings for OOM risks.
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
    Logger.info("Starting ResourceWatchdog check...")
    try do
      case System.cmd("docker", ["stats", "--no-stream", "--format", "{{.Name}}|{{.CPUPerc}}|{{.MemPerc}}"]) do
        {output, 0} ->
          lines = String.split(output, "\n", trim: true)
          Enum.each(lines, fn line ->
            [name, cpu_perc, mem_perc] = String.split(line, "|")
            Logger.info("Resource Watchdog: #{name} - CPU: #{cpu_perc}, RAM: #{mem_perc}")

            # Extract number from percentage (e.g. "95.5%")
            mem_val = parse_percentage(mem_perc)
            cpu_val = parse_percentage(cpu_perc)

            if mem_val >= 90.0 do
              Logger.warning("ResourceWatchdog Warning: High memory usage detected - OOM Risk for #{name}: #{mem_perc}")
            end

            if cpu_val >= 90.0 do
              Logger.warning("ResourceWatchdog Warning: High CPU usage detected for #{name}: #{cpu_perc}")
            end
          end)
        {error_msg, code} ->
          Logger.warning("ResourceWatchdog: Docker command returned non-zero code #{code}: #{error_msg}")
      end
    rescue
      _e in ErlangError -> Logger.warning("ResourceWatchdog: Docker command failed or docker is not installed.")
    end
    Logger.info("ResourceWatchdog check completed.")
  end

  defp parse_percentage(perc_str) do
    cleaned = String.replace(perc_str, "%", "") |> String.trim()
    case Float.parse(cleaned) do
      {val, _} -> val
      :error ->
        case Integer.parse(cleaned) do
          {val, _} -> val * 1.0
          :error -> 0.0
        end
    end
  end
end
