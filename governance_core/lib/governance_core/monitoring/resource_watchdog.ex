defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Resource Watchdog GenServer.
  Monitors CPU and memory usage of Docker containers dynamically.
  Logs warnings if usage exceeds 80%.
  """
  use GenServer
  require Logger

  @interval 60 * 1000 # Check every minute

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
          Logger.warning("docker stats returned code #{code}: #{error}")
      end
    rescue
      e in ErlangError ->
        Logger.debug("Failed to run docker stats (Docker may not be installed): #{inspect(e)}")
    end
  end

  defp parse_and_check_stats(output) do
    # Skip the header line
    lines = String.split(output, "\n", trim: true) |> Enum.drop(1)

    Enum.each(lines, fn line ->
      parts = String.split(line, ~r/\s{2,}/)

      if length(parts) >= 5 do
        container = Enum.at(parts, 0)
        cpu_str = Enum.at(parts, 2) |> String.trim_trailing("%")
        mem_str = Enum.at(parts, 4) |> String.trim_trailing("%")

        case {Float.parse(cpu_str), Float.parse(mem_str)} do
          {{cpu, _}, {mem, _}} ->
            if cpu > 80.0 do
              Logger.warning("Resource Watchdog: Container #{container} CPU usage is high: #{cpu}%")
            end

            if mem > 80.0 do
              Logger.warning("Resource Watchdog: Container #{container} Memory usage is high: #{mem}% (OOM risk)")
            end

          _ ->
            Logger.debug("Could not parse usage stats for container #{container}")
        end
      end
    end)
  end
end
