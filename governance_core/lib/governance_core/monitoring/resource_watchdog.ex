defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  A GenServer that monitors the resources (CPU and Memory) of agents running on
  Docker Swarm or K3s. Limits exceeding 80% will trigger warnings.
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
    schedule_watch()
    {:ok, state}
  end

  @impl true
  def handle_info(:watch, state) do
    perform_watch()
    schedule_watch()
    {:noreply, state}
  end

  defp schedule_watch do
    Process.send_after(self(), :watch, @interval)
  end

  defp perform_watch do
    Logger.info("Starting Resource Watchdog check...")

    try do
      case System.cmd("docker", ["stats", "--no-stream"]) do
        {output, 0} ->
          lines = String.split(output, "\n", trim: true)
          # Skip header line
          case lines do
            [_header | containers] ->
              Enum.each(containers, &check_container_stats/1)
            [] ->
              Logger.info("No running docker containers found.")
          end
        {err, code} ->
          Logger.warning("Docker stats command failed with code #{code}: #{inspect(err)}")
      end
    rescue
      e in ErlangError -> Logger.warning("Docker CLI not available: #{inspect(e)}")
    end
  end

  defp check_container_stats(line) do
    parts = String.split(line, ~r/\s{2,}/)

    if length(parts) >= 5 do
      container = Enum.at(parts, 0)
      cpu_str = Enum.at(parts, 2) |> String.trim_trailing("%")
      mem_str = Enum.at(parts, 4) |> String.trim_trailing("%")

      cpu_val = case Float.parse(cpu_str) do
        {val, _} -> val
        :error -> 0.0
      end

      mem_val = case Float.parse(mem_str) do
        {val, _} -> val
        :error -> 0.0
      end

      if cpu_val > 80.0 do
         Logger.warning("[Resource Watchdog] Container #{container} CPU usage is high: #{cpu_val}%")
      end

      if mem_val > 80.0 do
         Logger.warning("[Resource Watchdog] Container #{container} Memory usage is high: #{mem_val}%. OOM kill risk.")
      end
    else
      Logger.debug("Skipping unparseable docker stats line: #{line}")
    end
  end
end
