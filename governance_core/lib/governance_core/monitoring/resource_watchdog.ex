defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Monitors Docker Swarm / K3s resources for agents.
  Logs warnings if containers exceed 80% CPU or Memory limits.
  """
  use GenServer
  require Logger

  # 5 minutes in milliseconds
  @interval 5 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_watch()
    {:ok, state}
  end

  def handle_info(:watch, state) do
    check_resources()
    schedule_watch()
    {:noreply, state}
  end

  defp schedule_watch do
    Process.send_after(self(), :watch, @interval)
  end

  def check_resources do
    Logger.info("Running ResourceWatchdog checks...")

    try do
      case System.cmd("docker", ["stats", "--no-stream"]) do
        {output, 0} ->
          parse_and_log_stats(output)
        {_, code} ->
          Logger.error("Failed to run docker stats, exit code: #{code}")
      end
    rescue
      e in ErlangError ->
        Logger.error("Docker command not found or failed to execute: #{inspect(e)}")
    end
  end

  defp parse_and_log_stats(output) do
    lines = String.split(output, "\n", trim: true)

    # Skip the header line
    lines
    |> Enum.drop(1)
    |> Enum.each(fn line ->
      # Docker stats default output separates columns by multiple spaces
      parts = String.split(line, ~r/\s{2,}/)

      if length(parts) >= 5 do
        container_id = Enum.at(parts, 0)
        container_name = Enum.at(parts, 1)
        cpu_perc_str = Enum.at(parts, 2)
        mem_perc_str = Enum.at(parts, 4)

        cpu_val = parse_percentage(cpu_perc_str)
        mem_val = parse_percentage(mem_perc_str)

        if cpu_val > 80.0 do
          Logger.warning("Container #{container_name} (#{container_id}) CPU usage critical: #{cpu_val}%")
        end

        if mem_val > 80.0 do
          Logger.warning("Container #{container_name} (#{container_id}) Memory usage critical (OOM risk): #{mem_val}%")
        end
      end
    end)
  end

  defp parse_percentage(perc_str) do
    perc_str
    |> String.replace("%", "")
    |> String.trim()
    |> Float.parse()
    |> case do
      {val, _} -> val
      :error -> 0.0
    end
  end
end
