defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  A GenServer that continuously monitors agent Docker containers for high CPU and RAM usage.
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

  defp perform_monitoring do
    Logger.info("Starting Resource Watchdog monitoring...")

    try do
      case System.cmd("docker", ["stats", "--no-stream"]) do
        {output, 0} ->
          parse_and_check_stats(output)
        {_, code} ->
          Logger.error("docker stats command failed with exit code: #{code}")
      end
    rescue
      ErlangError ->
        Logger.error("docker command not found or failed to execute.")
    end
  end

  defp parse_and_check_stats(output) do
    # First line is header, skip it
    lines = String.split(output, "\n", trim: true) |> Enum.drop(1)

    Enum.each(lines, fn line ->
      columns = String.split(line, ~r/\s{2,}/)

      if length(columns) >= 5 do
        container_id = Enum.at(columns, 0)
        cpu_str = Enum.at(columns, 2)
        mem_str = Enum.at(columns, 4)

        check_usage(container_id, cpu_str, mem_str)
      else
        Logger.warning("Unexpected docker stats output format: #{line}")
      end
    end)
  end

  defp check_usage(container_id, cpu_str, mem_str) do
    cpu_val = parse_percentage(cpu_str)
    mem_val = parse_percentage(mem_str)

    if cpu_val > 80.0 do
      Logger.warning("Container #{container_id} CPU usage is high: #{cpu_val}%")
    end

    if mem_val > 80.0 do
      Logger.warning("Container #{container_id} Memory usage is high: #{mem_val}%")
    end
  end

  defp parse_percentage(str) do
    clean_str = String.replace(str, "%", "") |> String.trim()
    case Float.parse(clean_str) do
      {val, _} -> val
      :error ->
        case Integer.parse(clean_str) do
          {val, _} -> val * 1.0
          :error -> 0.0
        end
    end
  end
end
