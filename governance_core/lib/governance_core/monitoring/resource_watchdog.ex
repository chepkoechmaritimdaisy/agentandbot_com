defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  GenServer that continuously monitors Docker containers' CPU and RAM.
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
    Logger.info("Starting Resource Watchdog check...")

    try do
      case System.cmd("docker", ["stats", "--no-stream"]) do
        {output, 0} ->
          parse_and_log_stats(output)
        {error_output, code} ->
          Logger.warning("docker stats exited with code #{code}: #{error_output}")
      end
    rescue
      _e in ErlangError ->
        Logger.warning("docker CLI not found or failed to execute. Resource check skipped.")
    end
  end

  defp parse_and_log_stats(output) do
    # Skip the header line
    lines = String.split(output, "\n", trim: true) |> Enum.drop(1)

    Enum.each(lines, fn line ->
      # Default docker stats output columns separated by multiple spaces
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
              Logger.warning("Resource Watchdog: Container #{container} Memory usage is high: #{mem}%")
            end
          _ ->
            Logger.warning("Failed to parse resource stats for container #{container}")
        end
      end
    end)
  end
end
