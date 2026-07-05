defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Periodically checks Docker container resource usage using `docker stats --no-stream`.
  Logs warnings if CPU or memory usage exceeds 80%.
  """

  use GenServer
  require Logger

  @interval 5 * 60 * 1000 # 5 minutes

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_check()
    {:ok, state}
  end

  @impl true
  def handle_info(:check, state) do
    check_resources()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check, @interval)
  end

  def check_resources do
    try do
      case System.cmd("docker", ["stats", "--no-stream"]) do
        {output, 0} -> parse_and_warn(output)
        {error, _} -> Logger.error("ResourceWatchdog: docker stats failed: #{error}")
      end
    rescue
      e in ErlangError ->
        Logger.warning("ResourceWatchdog: Docker executable not found or failed: #{inspect(e)}")
    end
  end

  defp parse_and_warn(output) do
    # Skip header row
    output
    |> String.split("\n", trim: true)
    |> Enum.drop(1)
    |> Enum.each(&process_container_stats/1)
  end

  defp process_container_stats(line) do
    # docker stats output looks like:
    # CONTAINER ID   NAME      CPU %     MEM USAGE / LIMIT   MEM %     NET I/O   BLOCK I/O   PIDS
    # So we split by 2 or more spaces.
    parts = String.split(line, ~r/\s{2,}/)

    if length(parts) >= 5 do
      container = Enum.at(parts, 1)
      cpu_str = Enum.at(parts, 2) |> String.trim_trailing("%")
      mem_str = Enum.at(parts, 4) |> String.trim_trailing("%")

      case {Float.parse(cpu_str), Float.parse(mem_str)} do
        {{cpu, _}, {mem, _}} ->
          if cpu > 80.0 do
            Logger.warning("ResourceWatchdog: Container #{container} CPU usage is high: #{cpu}%")
          end
          if mem > 80.0 do
            Logger.warning("ResourceWatchdog: Container #{container} Memory usage is high: #{mem}%")
          end
        _ ->
          Logger.debug("ResourceWatchdog: Failed to parse float from stats for container #{container}")
      end
    end
  end
end
