defmodule GovernanceCore.ResourceWatchdog do
  @moduledoc """
  Monitors container CPU and RAM usage via `docker stats`.
  Logs warnings if limits are exceeded or OOM kill risk is detected.
  """
  use GenServer
  require Logger

  # Default check interval: 1 minute
  @interval 60_000

  # Example thresholds
  @cpu_threshold 90.0 # Percentage
  @ram_threshold 85.0 # Percentage

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
    Logger.debug("Running Resource Watchdog check...")

    case System.cmd("docker", ["stats", "--no-stream", "--format", "{{json .}}"]) do
      {output, 0} ->
        parse_and_check(output)
      {error_output, _} ->
        Logger.error("Failed to run docker stats: #{error_output}")
    end
  end

  defp parse_and_check(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.each(fn line ->
      case Jason.decode(line) do
        {:ok, stats} ->
          check_limits(stats)
        {:error, reason} ->
          Logger.error("Failed to parse docker stats JSON: #{inspect(reason)}")
      end
    end)
  end

  defp check_limits(stats) do
    container_name = Map.get(stats, "Name", "Unknown")

    cpu_str = Map.get(stats, "CPUPerc", "0.0%") |> String.replace("%", "")
    mem_str = Map.get(stats, "MemPerc", "0.0%") |> String.replace("%", "")

    cpu_val = parse_percentage(cpu_str)
    mem_val = parse_percentage(mem_str)

    if cpu_val > @cpu_threshold do
      Logger.warning("Resource Watchdog: Container #{container_name} exceeded CPU threshold (#{@cpu_threshold}%): #{cpu_val}%")
    end

    if mem_val > @ram_threshold do
      Logger.warning("Resource Watchdog: Container #{container_name} exceeded RAM threshold (#{@ram_threshold}%), risk of OOM kill: #{mem_val}%")
    end
  end

  defp parse_percentage(str) do
    case Float.parse(str) do
      {val, _} -> val
      :error -> 0.0
    end
  end
end
