defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Monitors Docker container resource quotas.
  Runs continuously to check CPU and Memory usage via `docker stats`.
  Logs warnings if either exceeds 80%.
  """
  use GenServer
  require Logger

  @interval 5 * 60 * 1000
  @threshold 80.0

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

  def perform_check do
    Logger.info("Starting Resource Watchdog check...")

    try do
      case System.cmd("docker", ["stats", "--no-stream"]) do
        {output, 0} ->
          parse_and_check_stats(output)
        {err, code} ->
          Logger.error("Failed to fetch docker stats: #{err} (code #{code})")
      end
    rescue
      e in ErlangError ->
        Logger.error("Docker command not found or failed to execute: #{inspect(e)}")
    end
  end

  defp parse_and_check_stats(output) do
    # Skip the header line
    lines = String.split(output, "\n", trim: true) |> Enum.drop(1)

    Enum.each(lines, fn line ->
      columns = String.split(line, ~r/\s{2,}/)

      if length(columns) >= 5 do
        # Format: CONTAINER ID | NAME | CPU % | MEM USAGE / LIMIT | MEM % | NET I/O | BLOCK I/O | PIDS
        container_name = Enum.at(columns, 1)
        cpu_str = Enum.at(columns, 2) |> String.replace("%", "")
        mem_str = Enum.at(columns, 4) |> String.replace("%", "")

        case {Float.parse(cpu_str), Float.parse(mem_str)} do
          {{cpu, _}, {mem, _}} ->
            if cpu > @threshold or mem > @threshold do
              Logger.warning("Resource Watchdog: Container #{container_name} exceeded limits! CPU: #{cpu}%, MEM: #{mem}%")
            end
          _ ->
            Logger.warning("Resource Watchdog: Failed to parse stats for #{container_name}: CPU(#{cpu_str}), MEM(#{mem_str})")
        end
      end
    end)
  end
end
