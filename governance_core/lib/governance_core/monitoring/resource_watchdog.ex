defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Monitors Docker container CPU and RAM usage by executing `docker stats --no-stream`.
  Logs warnings if CPU or memory usage exceeds 80%.
  """
  use GenServer
  require Logger

  @interval 60 * 1000 # 1 minute

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

  defp check_docker_stats do
    try do
      case System.cmd("docker", ["stats", "--no-stream"]) do
        {output, 0} -> parse_and_check_stats(output)
        {error, code} -> Logger.warning("Failed to run docker stats. Code: #{code}, Output: #{error}")
      end
    rescue
      e in ErlangError ->
        Logger.warning("Docker CLI not available or failed: #{inspect(e)}")
    end
  end

  defp parse_and_check_stats(output) do
    # Skip the header line
    lines = String.split(output, "\n", trim: true) |> Enum.drop(1)

    Enum.each(lines, fn line ->
      # docker stats output uses variable spaces for padding
      columns = String.split(line, ~r/\s{2,}/)

      if length(columns) >= 5 do
        # Format depends on docker version, but generally:
        # [CONTAINER ID, NAME, CPU %, MEM USAGE / LIMIT, MEM %]
        container_name = Enum.at(columns, 1)
        cpu_str = Enum.at(columns, 2)
        mem_str = Enum.at(columns, 4)

        check_thresholds(container_name, cpu_str, mem_str)
      end
    end)
  end

  defp check_thresholds(name, cpu_str, mem_str) do
    cpu_val = parse_percentage(cpu_str)
    mem_val = parse_percentage(mem_str)

    if cpu_val > 80.0 do
      Logger.warning("Resource Watchdog: Container #{name} CPU usage is high: #{cpu_val}%")
    end

    if mem_val > 80.0 do
      Logger.warning("Resource Watchdog: Container #{name} Memory usage is high: #{mem_val}% (OOM risk)")
    end
  end

  defp parse_percentage(str) do
    str
    |> String.replace("%", "")
    |> String.trim()
    |> Float.parse()
    |> case do
      {val, _} -> val
      :error -> 0.0
    end
  end
end
