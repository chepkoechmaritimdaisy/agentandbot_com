defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Periodically monitors container resources (CPU and RAM) using `docker stats`.
  Gracefully handles missing `docker` executables and non-zero exit codes.
  Logs warnings when limits are exceeded.
  """
  use GenServer
  require Logger

  # Default interval: 5 minutes
  @interval 5 * 60 * 1000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
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

  defp perform_watch do
    try do
      case System.cmd("docker", ["stats", "--no-stream", "--format", "{{.Name}}: {{.CPUPerc}}, {{.MemUsage}}"]) do
        {output, 0} ->
          process_stats(output)
        {error_msg, exit_code} ->
          Logger.warning("ResourceWatchdog: `docker stats` failed with code #{exit_code}: #{error_msg}")
      end
    rescue
      e in ErlangError ->
        Logger.warning("ResourceWatchdog: Could not execute `docker stats`. Is Docker installed? Exception: #{inspect(e)}")
    end
  end

  defp process_stats(output) do
    stats_lines = String.split(output, "\n", trim: true)

    Enum.each(stats_lines, fn line ->
      # Example format: container_name: 10.5%, 500MiB / 1GiB
      case String.split(line, ": ", parts: 2) do
        [name, metrics] ->
          case String.split(metrics, ", ", parts: 2) do
             [cpu_str, mem_str] ->
               check_limits(name, cpu_str, mem_str)
             _ ->
               Logger.warning("ResourceWatchdog: Could not parse metrics for #{name}: #{metrics}")
          end
        _ ->
          Logger.warning("ResourceWatchdog: Could not parse output line: #{line}")
      end
    end)
  end

  defp check_limits(name, cpu_str, _mem_str) do
     # Simple check for CPU > 80% as an example. More robust parsing is needed for production.
     cpu_val = cpu_str |> String.trim_trailing("%") |> Float.parse()

     case cpu_val do
       {val, _} when val > 80.0 ->
         Logger.warning("ResourceWatchdog: High CPU usage detected on container '#{name}': #{cpu_str}")
       _ ->
         :ok
     end
  end
end
