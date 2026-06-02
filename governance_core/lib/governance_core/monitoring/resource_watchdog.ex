defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  A GenServer that monitors Docker container resource usage continuously using `docker stats`.
  Logs warnings if CPU or memory usage exceeds 80%.
  """
  use GenServer
  require Logger

  # 5 minutes in milliseconds
  @interval 5 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_watch()
    {:ok, state}
  end

  def handle_info(:watch, state) do
    perform_watch()
    schedule_watch()
    {:noreply, state}
  end

  defp schedule_watch do
    Process.send_after(self(), :watch, @interval)
  end

  def perform_watch do
    Logger.debug("Starting continuous Resource Watchdog...")

    try do
      case System.cmd("docker", ["stats", "--no-stream"]) do
        {output, 0} ->
          parse_and_evaluate_stats(output)
        {_, code} ->
          Logger.warning("docker stats returned non-zero exit code: #{code}")
      end
    rescue
      e in ErlangError ->
        Logger.warning("Could not run docker stats: #{inspect(e)}")
    end
  end

  defp parse_and_evaluate_stats(output) do
    # docker stats default columns:
    # CONTAINER ID   NAME   CPU %   MEM USAGE / LIMIT   MEM %   NET I/O   BLOCK I/O   PIDS
    # Example line:
    # 3f3d7b420061   web    1.23%   123MiB / 1GiB       12.3%   1kB / 1kB 1MB / 1MB   10

    lines = String.split(output, "\n", trim: true)

    # Skip header
    lines = Enum.drop(lines, 1)

    Enum.each(lines, fn line ->
      parts = String.split(line, ~r/\s{2,}/)

      if length(parts) >= 5 do
        name = Enum.at(parts, 1)
        cpu_str = Enum.at(parts, 2)
        mem_str = Enum.at(parts, 4)

        cpu_val = parse_percentage(cpu_str)
        mem_val = parse_percentage(mem_str)

        if cpu_val > 80.0 do
          Logger.warning("ResourceWatchdog: Container #{name} CPU usage is high: #{cpu_str}")
        end

        if mem_val > 80.0 do
          Logger.warning("ResourceWatchdog: Container #{name} Memory usage is high: #{mem_str}")
        end
      end
    end)
  end

  defp parse_percentage(str) do
    # Removes the % sign and parses as float
    cleaned = String.replace(str, "%", "") |> String.trim()
    case Float.parse(cleaned) do
      {val, _} -> val
      :error -> 0.0
    end
  end
end
