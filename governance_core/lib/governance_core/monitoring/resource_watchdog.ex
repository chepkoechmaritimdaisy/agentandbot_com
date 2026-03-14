defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Monitors Docker container CPU and RAM usage dynamically using System.cmd.
  """
  use GenServer
  require Logger

  @interval 60_000 # Check every 1 minute

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
      {output, 0} = System.cmd("docker", ["stats", "--no-stream", "--format", "{{.Name}}: {{.CPUPerc}} CPU, {{.MemUsage}} RAM"])

      # Log resources
      lines = String.split(output, "\n", trim: true)
      Enum.each(lines, fn line ->
        # Simple heuristic, if CPU > 80% or MEM > 80%, log warning (hard to parse robustly without full stats parser)
        # We will just log all to warn for now or if they have specific keywords.
        Logger.info("Resource Watchdog: #{line}")

        # Check for high usage (basic check for "OOM kill" risk could look for MemUsage > 80% or specific values)
        # To avoid complex parsing of units (MiB, GiB, %), we simply log them for now.
        if String.contains?(line, "90.") or String.contains?(line, "100.00%") do
            Logger.warning("High resource usage detected! Risk of OOM kill. #{line}")
        end
      end)
    rescue
      e in ErlangError ->
        # docker executable might be missing
        Logger.warning("Resource Watchdog: Docker executable not found or failed to execute. #{inspect(e)}")
    end
  end
end
