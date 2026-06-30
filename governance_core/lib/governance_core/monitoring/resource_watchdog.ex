defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Monitors container CPU and RAM usage by safely invoking `docker stats --no-stream`.
  Logs warnings for resources exceeding 80% usage to help detect OOM risks or limit breaches.
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
    perform_check()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check, @interval)
  end

  def perform_check do
    try do
      case System.cmd("docker", ["stats", "--no-stream"]) do
        {output, 0} ->
          process_stats(output)
        {error_output, code} ->
          Logger.error("Resource Watchdog: docker stats failed with code #{code}. Output: #{error_output}")
      end
    rescue
      e in ErlangError ->
        Logger.error("Resource Watchdog: Failed to execute docker command: #{inspect(e)}")
    end
  end

  defp process_stats(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.drop(1) # Drop header row
    |> Enum.each(&analyze_container_stats/1)
  end

  defp analyze_container_stats(line) do
    parts = String.split(line, ~r/\s{2,}/)

    if length(parts) >= 5 do
      container_id = Enum.at(parts, 0)
      name = Enum.at(parts, 1)
      cpu_str = Enum.at(parts, 2)
      mem_str = Enum.at(parts, 4) # Index 4 is MEM %

      check_threshold(container_id, name, "CPU", parse_percentage(cpu_str))
      check_threshold(container_id, name, "Memory", parse_percentage(mem_str))
    end
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

  defp check_threshold(id, name, type, value) do
    if value > 80.0 do
      Logger.warning("Resource Watchdog ALERT: Container #{name} (#{id}) #{type} usage is critically high at #{value}%")
    end
  end
end
