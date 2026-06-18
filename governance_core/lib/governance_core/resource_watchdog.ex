defmodule GovernanceCore.ResourceWatchdog do
  @moduledoc """
  Monitors container CPU and RAM usage via `docker stats`.
  Logs warnings for quota limits and potential OOM risks dynamically.
  """
  use GenServer
  require Logger

  # Run every 5 minutes
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
    Logger.info("Running Resource Watchdog checks...")

    try do
      {output, status} = System.cmd("docker", ["stats", "--no-stream", "--format", "{{json .}}"])

      if status == 0 do
        output
        |> String.split("\n", trim: true)
        |> Enum.each(&parse_and_evaluate_stats/1)
      else
        Logger.error("Failed to run docker stats. Status code: #{status}")
      end
    rescue
      e -> Logger.error("Error executing docker stats command: #{inspect(e)}")
    end
  end

  defp parse_and_evaluate_stats(json_line) do
    case Jason.decode(json_line) do
      {:ok, stats} ->
        container_name = Map.get(stats, "Name", "unknown")
        cpu_perc_str = Map.get(stats, "CPUPerc", "0.0%")
        mem_perc_str = Map.get(stats, "MemPerc", "0.0%")

        cpu_val = parse_percentage(cpu_perc_str)
        mem_val = parse_percentage(mem_perc_str)

        # Assuming > 80% is warning limit
        if cpu_val > 80.0 do
          Logger.warning("[ResourceWatchdog] Container #{container_name} CPU usage is high: #{cpu_perc_str}")
        end

        if mem_val > 85.0 do
          Logger.warning("[ResourceWatchdog] Container #{container_name} Memory usage is critical: #{mem_perc_str}. Potential OOM risk!")
        end

      {:error, reason} ->
        Logger.error("Failed to parse docker stats JSON: #{inspect(reason)}")
    end
  end

  defp parse_percentage(perc_str) do
    # Strip '%' and whitespace
    clean_str = perc_str |> String.replace("%", "") |> String.trim()
    case Float.parse(clean_str) do
      {val, _} -> val
      :error -> 0.0
    end
  end
end
