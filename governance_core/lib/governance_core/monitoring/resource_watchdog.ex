defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Monitors Docker Swarm or K3s containers for resource usage (CPU and RAM).
  Logs warnings if containers exceed 80% usage limits, indicating OOM risks.
  """
  use GenServer
  require Logger

  # 5 minutes in milliseconds
  @interval 5 * 60 * 1000

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
    Logger.debug("Starting Resource Watchdog check...")

    try do
      case System.cmd("docker", ["stats", "--no-stream"]) do
        {output, 0} ->
          parse_and_evaluate_stats(output)

        {_output, exit_code} ->
          Logger.error("Failed to retrieve docker stats, exit code: #{exit_code}")
      end
    rescue
      e in ErlangError ->
        Logger.error("docker CLI missing or failed: #{inspect(e)}")
    end
  end

  defp parse_and_evaluate_stats(output) do
    output
    |> String.split("\n", trim: true)
    # Drop the header row
    |> Enum.drop(1)
    |> Enum.each(&evaluate_container/1)
  end

  defp evaluate_container(line) do
    columns = String.split(line, ~r/\s{2,}/)

    if length(columns) >= 5 do
      container_id = Enum.at(columns, 0)
      name = Enum.at(columns, 1)
      cpu_str = Enum.at(columns, 2)
      mem_str = Enum.at(columns, 4)

      cpu_usage = parse_percentage(cpu_str)
      mem_usage = parse_percentage(mem_str)

      if cpu_usage > 80.0 do
        Logger.warning("Resource Watchdog: Container #{name} (#{container_id}) CPU usage critical: #{cpu_usage}%")
      end

      if mem_usage > 80.0 do
        Logger.warning("Resource Watchdog: Container #{name} (#{container_id}) RAM usage critical: #{mem_usage}% (OOM risk)")
      end
    end
  end

  defp parse_percentage(str) do
    str
    |> String.replace("%", "")
    |> String.trim()
    |> Float.parse()
    |> case do
      {float_val, _} -> float_val
      :error -> 0.0
    end
  end
end
