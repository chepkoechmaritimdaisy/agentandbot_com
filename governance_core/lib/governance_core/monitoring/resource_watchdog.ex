defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Periodically monitors Docker Swarm or K3s containers for resource usage (CPU and RAM).
  Logs warnings if limits (80%) are exceeded.
  """
  use GenServer
  require Logger

  @interval 60_000 # Check every minute

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
    try do
      case System.cmd("docker", ["stats", "--no-stream"]) do
        {output, 0} ->
          parse_and_check_stats(output)
        {output, exit_code} ->
          Logger.error("ResourceWatchdog docker stats failed with exit code #{exit_code}: #{output}")
      end
    rescue
      e in ErlangError ->
        # Handle cases where docker is missing completely
        Logger.error("ResourceWatchdog failed to run docker command: #{inspect(e)}")
    end
  end

  defp parse_and_check_stats(output) do
    # Skip the header line and process the rest
    lines = output |> String.split("\n", trim: true) |> Enum.drop(1)

    Enum.each(lines, fn line ->
      parts = String.split(line, ~r/\s{2,}/)

      if length(parts) >= 5 do
        # CONTAINER ID | NAME | CPU % | MEM USAGE / LIMIT | MEM % | NET I/O | BLOCK I/O | PIDS
        container_id = Enum.at(parts, 0)
        cpu_str = Enum.at(parts, 2) |> String.replace("%", "")
        mem_str = Enum.at(parts, 4) |> String.replace("%", "")

        case {Float.parse(cpu_str), Float.parse(mem_str)} do
          {{cpu, _}, {mem, _}} ->
            if cpu > 80.0 do
              Logger.warning("ResourceWatchdog: Container #{container_id} CPU usage critical: #{cpu}%")
            end

            if mem > 80.0 do
              Logger.warning("ResourceWatchdog: Container #{container_id} Memory usage critical: #{mem}% - OOM Kill risk")
            end
          _ ->
            :ok
        end
      end
    end)
  end
end
