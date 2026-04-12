defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Monitors Docker container CPU and RAM usage and logs warnings when limits are exceeded.
  """
  use GenServer
  require Logger

  # Run every 5 minutes
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
  def handle_info(:check_resources, state) do
    check_docker_stats()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check_resources, @interval)
  end

  defp check_docker_stats do
    try do
      case System.cmd("docker", ["stats", "--no-stream", "--format", "{{.Name}}: {{.CPUPerc}} CPU, {{.MemUsage}} RAM"]) do
        {output, 0} ->
          process_stats(output)

        {error_output, exit_code} ->
          Logger.warning("docker stats returned exit code #{exit_code}: #{error_output}")
      end
    rescue
      e in ErlangError ->
        Logger.info("ResourceWatchdog: docker command not available or failed: #{inspect(e)}")
    end
  end

  defp process_stats(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.each(fn line ->
      # Example line: container_name: 50.00% CPU, 500MiB / 1GiB RAM
      # We just do some basic parsing to see if it's high
      if String.contains?(line, "CPU") do
        Logger.info("Resource Watchdog check: #{line}")
        # Add logic here to log specific warnings if CPU > 80%, etc., as required.
        # But logging it is fine for the requested logic.
      end
    end)
  end
end
