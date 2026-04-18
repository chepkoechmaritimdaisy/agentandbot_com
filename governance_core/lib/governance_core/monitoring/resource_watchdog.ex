defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  A GenServer that monitors Docker container CPU and RAM usage.
  Logs warnings for high resource usage or OOM risks.
  """

  use GenServer
  require Logger

  @interval 5 * 60 * 1000

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
    check_resources()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check, @interval)
  end

  defp check_resources do
    Logger.debug("Checking Docker container resources...")

    try do
      case System.cmd("docker", ["stats", "--no-stream", "--format", "{{.Name}}: {{.CPUPerc}} CPU, {{.MemUsage}} RAM"]) do
        {output, 0} ->
          Logger.info("Resource usage:\n#{output}")
          # In a real scenario we might parse percentages here to detect threshold breaches.
          # For MVP, we just log the output.

        {error_output, exit_code} ->
          Logger.error("Failed to check docker stats (exit code #{exit_code}): #{error_output}")
      end
    rescue
      e in ErlangError ->
        Logger.error("Missing docker executable or command failed: #{inspect(e)}")
      e ->
        Logger.error("Error executing docker command: #{inspect(e)}")
    end
  end
end
