defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Periodically monitors container CPU and RAM usage via docker stats.
  """
  use GenServer
  require Logger

  # 5 minutes in milliseconds
  @interval 5 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_watchdog()
    {:ok, state}
  end

  @impl true
  def handle_info(:watchdog, state) do
    perform_watchdog_check()
    schedule_watchdog()
    {:noreply, state}
  end

  defp schedule_watchdog do
    Process.send_after(self(), :watchdog, @interval)
  end

  def perform_watchdog_check do
    Logger.info("ResourceWatchdog: Checking Docker container resources...")

    try do
      case System.cmd("docker", ["stats", "--no-stream"]) do
        {output, 0} ->
          parse_and_check_stats(output)

        {error_output, exit_code} ->
          Logger.warning("ResourceWatchdog: docker stats failed with exit code #{exit_code}: #{error_output}")
      end
    rescue
      e in ErlangError ->
        Logger.warning("ResourceWatchdog: ErlangError running docker stats (docker might not be installed): #{inspect(e)}")
    end
  end

  defp parse_and_check_stats(output) do
    # Skip the header line
    lines = String.split(output, "\n", trim: true) |> Enum.drop(1)

    Enum.each(lines, fn line ->
      # Split by 2 or more spaces
      parts = String.split(line, ~r/\s{2,}/)

      if length(parts) >= 5 do
        container = Enum.at(parts, 0)
        cpu_str = Enum.at(parts, 2)
        mem_str = Enum.at(parts, 4)

        cpu_val = parse_percentage(cpu_str)
        mem_val = parse_percentage(mem_str)

        if cpu_val > 80.0 do
          Logger.warning("ResourceWatchdog: Container #{container} CPU usage is high: #{cpu_val}%")
        end

        if mem_val > 80.0 do
          Logger.warning("ResourceWatchdog: Container #{container} Memory usage is high: #{mem_val}%")
        end
      end
    end)
  end

  defp parse_percentage(percent_str) do
    # "1.50%" -> 1.50
    cleaned = String.replace(percent_str, "%", "") |> String.trim()

    case Float.parse(cleaned) do
      {float_val, _} -> float_val
      :error -> 0.0
    end
  end
end
