defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Monitors Docker container CPU and RAM usage and logs warnings if limits are exceeded.
  """
  use GenServer
  require Logger

  # Check every 1 minute
  @interval 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_check()
    {:ok, state}
  end

  def handle_info(:check, state) do
    check_resources()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check, @interval)
  end

  defp check_resources do
    try do
      case System.cmd("docker", ["stats", "--no-stream"]) do
        {output, 0} ->
          parse_and_evaluate(output)
        {output, code} ->
          Logger.error("Failed to run docker stats, exit code #{code}: #{output}")
      end
    rescue
      e in ErlangError ->
        Logger.error("docker CLI not found or failed to execute: #{inspect(e)}")
    end
  end

  defp parse_and_evaluate(output) do
    output
    |> String.split("\n", trim: true)
    # Skip header
    |> Enum.drop(1)
    |> Enum.each(&evaluate_line/1)
  end

  defp evaluate_line(line) do
    parts = String.split(line, ~r/\s{2,}/)

    if length(parts) >= 5 do
      container_id = Enum.at(parts, 0)
      cpu_str = Enum.at(parts, 2)
      mem_str = Enum.at(parts, 4)

      cpu_usage = parse_percentage(cpu_str)
      mem_usage = parse_percentage(mem_str)

      if cpu_usage > 80.0 do
        Logger.warning("Container #{container_id} CPU usage is high: #{cpu_usage}%")
      end

      if mem_usage > 80.0 do
        Logger.warning("Container #{container_id} Memory usage is high: #{mem_usage}%. Risk of OOM kill.")
      end
    end
  end

  defp parse_percentage(str) do
    str
    |> String.replace("%", "")
    |> String.trim()
    |> Float.parse()
    |> case do
      {float, _} -> float
      :error -> 0.0
    end
  end
end
