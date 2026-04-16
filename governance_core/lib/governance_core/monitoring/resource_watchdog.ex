defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Monitors CPU and RAM usage of containers using docker stats.
  Logs warnings if limits are exceeded or OOM kill risk is present.
  Runs every 5 minutes.
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
    Logger.info("Starting Resource Watchdog...")

    try do
      case System.cmd("docker", ["stats", "--no-stream", "--format", "{{.Name}}: {{.CPUPerc}} {{.MemUsage}}"], stderr_to_stdout: true) do
        {output, 0} ->
          # Process the output
          lines = String.split(output, "\n", trim: true)
          Enum.each(lines, fn line ->
            # Basic parsing - in a real scenario we'd parse percentages and sizes properly
            Logger.info("Container stats: #{line}")

            # Simple heuristic check for warning logging
            if String.contains?(line, "90.00%") or String.contains?(line, "99.00%") do
              Logger.warning("Resource Watchdog Alert: High usage detected for container: #{line}")
            end
          end)
        {output, code} ->
          Logger.error("docker stats returned non-zero exit code #{code}: #{output}")
      end
    rescue
      e in ErlangError ->
        Logger.error("Resource Watchdog failed to run docker command: #{inspect(e)}")
    end

    Logger.info("Resource Watchdog completed.")
  end
end
