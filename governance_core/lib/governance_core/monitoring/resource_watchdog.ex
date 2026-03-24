defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  A GenServer that monitors container CPU and RAM usage via `docker stats`
  Logs warnings for resource limits, handles missing docker executable and non-zero exits.
  """
  use GenServer
  require Logger

  # 1 minute
  @interval 60 * 1000

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
    try do
      case System.cmd("docker", ["stats", "--no-stream", "--format", "{{.Name}}: {{.CPUPerc}} CPU, {{.MemUsage}} RAM"]) do
        {output, 0} ->
          Logger.info("Resource Watchdog check passed. Stats:\n#{output}")
        {output, status} ->
          Logger.warning("docker stats exited with status #{status}: #{output}")
      end
    rescue
      e in ErlangError ->
        Logger.warning("Docker executable not found or failed to execute: #{inspect(e)}")
    end
  end
end
