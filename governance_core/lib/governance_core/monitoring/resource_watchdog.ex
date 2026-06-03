defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Monitors Docker container CPU and RAM usage dynamically using docker stats.
  Logs warnings if usage exceeds 80%.
  """
  use GenServer
  require Logger

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

  defp perform_watch do
    try do
      case System.cmd("docker", ["stats", "--no-stream"]) do
        {output, 0} ->
          parse_and_check_stats(output)

        {output, exit_code} ->
          Logger.debug("ResourceWatchdog: docker stats failed with exit #{exit_code}: #{output}")
      end
    rescue
      e in ErlangError ->
        Logger.debug("ResourceWatchdog: Docker executable not found or failed: #{inspect(e)}")
    end
  end

  defp parse_and_check_stats(output) do
    # Skip the header line
    lines = String.split(output, "\n", trim: true) |> Enum.drop(1)

    Enum.each(lines, fn line ->
      parts = String.split(line, ~r/\s{2,}/)

      if length(parts) >= 5 do
        container_id = Enum.at(parts, 0)
        container_name = Enum.at(parts, 1)
        cpu_str = Enum.at(parts, 2) |> String.trim_trailing("%")
        mem_str = Enum.at(parts, 4) |> String.trim_trailing("%")

        cpu_val = parse_percentage(cpu_str)
        mem_val = parse_percentage(mem_str)

        if cpu_val > 80.0 do
          Logger.warning("ResourceWatchdog: Container #{container_name} (#{container_id}) CPU usage is high: #{cpu_val}%")
        end

        if mem_val > 80.0 do
          Logger.warning("ResourceWatchdog: Container #{container_name} (#{container_id}) Memory usage is high: #{mem_val}%")
        end
      end
    end)
  end

  defp parse_percentage(str) do
    case Float.parse(str) do
      {val, _} -> val
      :error -> 0.0
    end
  end
end
