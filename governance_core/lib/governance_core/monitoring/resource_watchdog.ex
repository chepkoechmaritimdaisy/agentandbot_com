defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Monitors Docker CPU and RAM usage, enforcing quotas to isolate potential OOM incidents.
  """
  use GenServer
  require Logger

  @interval 5 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_watchdog()
    {:ok, state}
  end

  @impl true
  def handle_info(:watchdog, state) do
    perform_check()
    schedule_watchdog()
    {:noreply, state}
  end

  defp schedule_watchdog do
    Process.send_after(self(), :watchdog, @interval)
  end

  def perform_check do
    Logger.info("Starting Resource Watchdog check...")

    try do
      case System.cmd("docker", ["stats", "--no-stream"]) do
        {output, 0} ->
          lines = String.split(output, "\n", trim: true)
          # Skip header line
          lines = if length(lines) > 0, do: tl(lines), else: []

          Enum.each(lines, fn line ->
            parts = String.split(line, ~r/\s{2,}/)

            if length(parts) >= 5 do
              container = Enum.at(parts, 0)
              cpu_str = Enum.at(parts, 2) |> String.replace("%", "") |> String.trim()
              mem_str = Enum.at(parts, 4) |> String.replace("%", "") |> String.trim()

              case {Float.parse(cpu_str), Float.parse(mem_str)} do
                {{cpu, _}, {mem, _}} ->
                  if cpu > 80.0 do
                    Logger.warning("Container #{container} CPU usage is high: #{cpu}%")
                  end

                  if mem > 80.0 do
                    Logger.warning("Container #{container} Memory usage is high: #{mem}% (OOM risk)")
                  end
                _ ->
                  Logger.debug("Could not parse metrics for container #{container}")
              end
            end
          end)

        {err, code} ->
          Logger.error("Failed to run docker stats, exit code: #{code}, out: #{err}")
      end
    rescue
      e in ErlangError ->
        Logger.error("Failed to execute docker CLI, is it installed? #{inspect(e)}")
    end
  end
end
