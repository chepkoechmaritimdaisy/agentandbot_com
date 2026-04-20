defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Monitors container CPU and RAM usage dynamically, logging warnings.
  Utilizes docker stats.
  """

  use GenServer
  require Logger

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

  defp perform_check do
    Logger.info("Starting Resource Watchdog Check...")

    try do
      case System.cmd("docker", ["stats", "--no-stream", "--format", "{{.Name}}: {{.CPUPerc}} / {{.MemUsage}}"]) do
        {output, 0} ->
          # Just log the output for now
          Logger.info("Resource Usage:\n#{output}")
          # One could parse this and check for "OOM kill" risks if limits were known.

        {output, exit_code} ->
          Logger.warning("Docker stats failed with code #{exit_code}: #{output}")
      end
    rescue
      e in ErlangError ->
        Logger.warning("Docker executable might be missing: #{inspect(e)}")
    end
  end
end
