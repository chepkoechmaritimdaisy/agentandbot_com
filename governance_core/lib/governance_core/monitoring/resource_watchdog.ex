defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  A GenServer that monitors Docker container CPU and Memory usage dynamically.
  Runs every 5 minutes and logs warnings if usage exceeds 80%.
  """
  use GenServer
  require Logger

  @interval 5 * 60 * 1000 # 5 minutes

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

  def perform_watch do
    Logger.info("Resource Watchdog: Checking container stats...")

    try do
      case System.cmd("docker", ["stats", "--no-stream"]) do
        {output, 0} ->
          parse_and_check_stats(output)
        {output, _exit_code} ->
          Logger.warning("Resource Watchdog: Failed to run docker stats: #{output}")
      end
    rescue
      e in ErlangError ->
        Logger.error("Resource Watchdog: Could not execute docker command. Error: #{inspect(e)}")
    end
  end

  defp parse_and_check_stats(output) do
    lines = String.split(output, "\n", trim: true)

    # Skip the header line
    case lines do
      [_header | container_lines] ->
        Enum.each(container_lines, fn line ->
          parts = String.split(line, ~r/\s{2,}/)
          if length(parts) >= 5 do
            container_id = Enum.at(parts, 0)
            cpu_str = Enum.at(parts, 2)
            mem_str = Enum.at(parts, 4)

            check_usage(container_id, "CPU", cpu_str)
            check_usage(container_id, "Memory", mem_str)
          end
        end)
      _ ->
        Logger.info("Resource Watchdog: No container data found.")
    end
  end

  defp check_usage(container_id, type, usage_str) do
    # usage_str might be like "0.54%"
    clean_str = String.replace(usage_str, "%", "") |> String.trim()

    case Float.parse(clean_str) do
      {usage, _rest} ->
        if usage > 80.0 do
          Logger.warning("Resource Watchdog: Container #{container_id} has high #{type} usage: #{usage}%. OOM/Throttling risk.")
        end
      :error ->
        # Ignore unparseable
        :ok
    end
  end
end
