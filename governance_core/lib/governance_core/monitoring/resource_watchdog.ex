defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Monitors Docker container CPU and RAM usage dynamically.
  Logs warnings for containers exceeding resource limits or at risk of OOM.
  """
  use GenServer
  require Logger

  # Check interval: 60 seconds
  @interval 60_000

  # Example thresholds (can be made configurable)
  @cpu_threshold 80.0
  @mem_threshold 80.0

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("Starting ResourceWatchdog")
    schedule_check()
    {:ok, %{}}
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
    try do
      # Format: container_id, name, cpu_perc, mem_perc
      case System.cmd("docker", ["stats", "--no-stream", "--format", "{{.ID}},{{.Name}},{{.CPUPerc}},{{.MemPerc}}"]) do
        {output, 0} ->
          process_stats(output)
        {error, code} ->
          Logger.warning("ResourceWatchdog: docker stats failed with code #{code}: #{error}")
      end
    rescue
      e in ErlangError ->
        # Handle missing docker executable gracefully
        case e do
          %ErlangError{original: :enoent} ->
            Logger.debug("ResourceWatchdog: docker executable not found, skipping checks.")
          _ ->
            Logger.warning("ResourceWatchdog: Failed to execute docker command: #{inspect(e)}")
        end
    end
  end

  defp process_stats(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.each(&analyze_container_stats/1)
  end

  defp analyze_container_stats(line) do
    case String.split(line, ",") do
      [id, name, cpu_str, mem_str] ->
        cpu = parse_percentage(cpu_str)
        mem = parse_percentage(mem_str)

        if cpu > @cpu_threshold do
          Logger.warning("ResourceWatchdog: Container #{name} (#{id}) is exceeding CPU limits: #{cpu}%")
        end

        if mem > @mem_threshold do
          Logger.warning("ResourceWatchdog: Container #{name} (#{id}) is at risk of OOM. Memory usage: #{mem}%")
        end
      _ ->
        Logger.debug("ResourceWatchdog: Unrecognized docker stats format: #{line}")
    end
  end

  defp parse_percentage(str) do
    # Remove '%' and parse to float
    clean_str = String.replace(str, "%", "")
    case Float.parse(clean_str) do
      {val, _} -> val
      :error -> 0.0
    end
  end
end
