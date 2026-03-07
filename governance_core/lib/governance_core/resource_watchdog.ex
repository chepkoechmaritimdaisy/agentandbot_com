defmodule GovernanceCore.ResourceWatchdog do
  @moduledoc """
  Monitors container CPU and RAM usage periodically.
  Generates warning logs for containers exceeding predefined limits or showing OOM risks.
  """
  use GenServer
  require Logger

  # 5 minutes
  @interval 5 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_check()
    {:ok, state}
  end

  def handle_info(:check_resources, state) do
    perform_check()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check_resources, @interval)
  end

  def perform_check do
    case System.cmd("docker", ["stats", "--no-stream", "--format", "{{.Name}}: {{.CPUPerc}} CPU, {{.MemUsage}} RAM"]) do
      {output, 0} ->
        parse_and_log_stats(output)
      {error, _exit_code} ->
        Logger.error("Resource Watchdog failed to fetch docker stats: #{inspect(error)}")
    end
  end

  defp parse_and_log_stats(output) do
    String.split(output, "\n", trim: true)
    |> Enum.each(&analyze_container_stat/1)
  end

  defp analyze_container_stat(stat_line) do
    # Simple warning log for now, can be expanded to parse thresholds dynamically
    # Example stats format: "agent1: 1.50% CPU, 128MiB / 2GiB RAM"

    if String.contains?(stat_line, "90.") or String.contains?(stat_line, "100.00%") do
      Logger.warning("Resource Watchdog Alert: High usage detected! #{stat_line}")
    end
  end
end
