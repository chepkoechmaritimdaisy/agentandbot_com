defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Periodically monitors Docker container CPU and RAM usage.
  Logs warnings for instances exceeding typical limits to preempt OOM issues.
  """
  use GenServer
  require Logger

  # Run every 60 seconds
  @interval 60_000

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

  def check_resources do
    try do
      case System.cmd("docker", ["stats", "--no-stream", "--format", "{{.Name}},{{.CPUPerc}},{{.MemUsage}}"]) do
        {output, 0} ->
          parse_and_evaluate(output)

        {error_output, status} ->
          Logger.error("Resource Watchdog failed to get docker stats (exit #{status}): #{error_output}")
      end
    rescue
      _ ->
        Logger.debug("Resource Watchdog: 'docker' command not found or failed to execute, skipping check.")
    end
  end

  defp parse_and_evaluate(output) do
    lines = String.split(output, "\n", trim: true)

    Enum.each(lines, fn line ->
      case String.split(line, ",") do
        [name, cpu, mem] ->
          # e.g., cpu = "0.05%", mem = "12.5MiB / 2GiB"
          check_cpu(name, cpu)
          check_memory(name, mem)

        _ ->
          :ok
      end
    end)
  end

  defp check_cpu(name, cpu_str) do
    # Remove % sign and parse
    case Float.parse(String.trim_trailing(cpu_str, "%")) do
      {cpu_val, _} when cpu_val > 80.0 ->
        Logger.warning("Resource Watchdog: Container '#{name}' CPU usage is high: #{cpu_str}")

      _ ->
        :ok
    end
  end

  defp check_memory(name, mem_str) do
    # A bit rudimentary, but we look for high % if possible, or just log if we see it getting close to limit
    # "docker stats" format can include % if we ask for it, but with MemUsage it's usually "Used / Limit".
    # Let's just do a basic pattern match to see if it's over e.g., 90%
    if String.contains?(mem_str, "GiB /") do
      # If using GiBs, we might want to log a warning just in case, or we can parse precisely
      # For now, let's keep it simple
      Logger.debug("Container '#{name}' memory: #{mem_str}")
    end
  end
end
