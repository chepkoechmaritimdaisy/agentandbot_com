defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Periodically monitors Docker resources using `docker stats --no-stream` to prevent OOM
  and high CPU usage.
  """
  use GenServer
  require Logger

  # 5 minutes
  @interval 5 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_check()
    {:ok, state}
  end

  def handle_info(:check_resources, state) do
    check_resources()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check_resources, @interval)
  end

  def check_resources do
    Logger.info("Starting Resource Watchdog check...")

    try do
      case System.cmd("docker", ["stats", "--no-stream"]) do
        {output, 0} ->
          parse_and_log_stats(output)
        {_, code} ->
          Logger.warning("docker stats returned non-zero exit code: #{code}")
      end
    rescue
      e in ErlangError ->
        Logger.warning("Docker CLI missing or unavailable for Watchdog: #{inspect(e)}")
      e ->
        Logger.error("Resource Watchdog error: #{inspect(e)}")
    catch
      :exit, _ ->
        Logger.error("docker stats command failed")
    end
  end

  defp parse_and_log_stats(output) do
    # docker stats output roughly looks like:
    # CONTAINER ID   NAME      CPU %     MEM USAGE / LIMIT     MEM %     NET I/O     BLOCK I/O   PIDS
    # 2b34a...       my_con    12.3%     50MiB / 1GiB          5.0%      10B / 0B    0B / 0B     1

    # Skip header
    lines = String.split(output, "\n", trim: true) |> Enum.drop(1)

    Enum.each(lines, fn line ->
      parts = String.split(line, ~r/\s{2,}/)

      if length(parts) >= 5 do
        # CPU is at index 2
        cpu_str = Enum.at(parts, 2)
        # MEM is at index 4
        mem_str = Enum.at(parts, 4)
        name = Enum.at(parts, 1)

        cpu_val = parse_percentage(cpu_str)
        mem_val = parse_percentage(mem_str)

        if cpu_val > 80.0 do
          Logger.warning("Resource Watchdog: Container #{name} CPU usage high: #{cpu_val}%")
        end

        if mem_val > 80.0 do
          Logger.warning("Resource Watchdog: Container #{name} Memory usage high (OOM risk): #{mem_val}%")
        end
      end
    end)
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
