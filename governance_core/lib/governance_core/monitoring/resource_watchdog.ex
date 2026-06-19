defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Monitors container CPU and RAM usage via `docker stats`.
  Logs warnings if thresholds are exceeded (e.g., >80%).
  """
  use GenServer
  require Logger

  # Interval: 30 seconds
  @interval 30_000

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
          parse_and_evaluate(output)
        {err, code} ->
          Logger.error("ResourceWatchdog: Failed to run docker stats (exit #{code}): #{err}")
      end
    rescue
      e in ErlangError ->
        Logger.warning("ResourceWatchdog: Docker executable not found or failed to execute: #{inspect(e)}")
    end
  end

  defp parse_and_evaluate(output) do
    lines = String.split(output, "\n", trim: true) |> tl() # Skip header

    Enum.each(lines, fn line ->
      parts = String.split(line, ~r/\s{2,}/)

      if length(parts) >= 5 do
        # parts[0] = Container ID/Name
        # parts[2] = CPU % (e.g. "1.50%")
        # parts[4] = MEM % (e.g. "4.00%")
        container = Enum.at(parts, 0)
        cpu_str = Enum.at(parts, 2)
        mem_str = Enum.at(parts, 4)

        cpu = parse_percentage(cpu_str)
        mem = parse_percentage(mem_str)

        if cpu > 80.0 do
          Logger.warning("ResourceWatchdog: CRITICAL - Container #{container} CPU usage at #{cpu}%")
        end

        if mem > 80.0 do
          Logger.warning("ResourceWatchdog: CRITICAL - Container #{container} MEM usage at #{mem}% (OOM Risk)")
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
