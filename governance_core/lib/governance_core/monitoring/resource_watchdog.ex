defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Resource Watchdog GenServer that continuously monitors container CPU
  and RAM usage dynamically via `docker stats --no-stream` and logs
  warnings if usage exceeds thresholds.
  """
  use GenServer
  require Logger

  # 5 minutes in milliseconds
  @interval 5 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_check()
    {:ok, state}
  end

  @impl true
  def handle_info(:check_resources, state) do
    check_resources()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check_resources, @interval)
  end

  defp check_resources do
    try do
      case System.cmd("docker", ["stats", "--no-stream"]) do
        {output, 0} ->
          parse_and_check_stats(output)

        {error, code} ->
          Logger.error("Failed to run docker stats. Exit code: #{code}, Output: #{error}")
      end
    rescue
      e in ErlangError ->
        Logger.error("docker executable not found or failed to execute: #{inspect(e)}")
    end
  end

  defp parse_and_check_stats(output) do
    # Skip the header line
    lines =
      output
      |> String.split("\n", trim: true)
      |> Enum.drop(1)

    Enum.each(lines, fn line ->
      parts = String.split(line, ~r/\s{2,}/)

      if length(parts) >= 5 do
        container_id = Enum.at(parts, 0)
        cpu_str = Enum.at(parts, 2)
        mem_str = Enum.at(parts, 4)

        check_thresholds(container_id, cpu_str, mem_str)
      end
    end)
  end

  defp check_thresholds(container_id, cpu_str, mem_str) do
    cpu_val = parse_percentage(cpu_str)
    mem_val = parse_percentage(mem_str)

    if cpu_val > 80.0 do
      Logger.warning("Resource Watchdog: Container #{container_id} CPU usage high: #{cpu_val}%")
    end

    if mem_val > 80.0 do
      Logger.warning("Resource Watchdog: Container #{container_id} Memory usage high: #{mem_val}%")
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
