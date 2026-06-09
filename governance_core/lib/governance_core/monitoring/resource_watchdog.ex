defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Monitors container CPU and RAM usage by calling `docker stats --no-stream`.
  Logs warnings if CPU or memory usage exceeds 80%.
  """
  use GenServer
  require Logger

  # Check every minute
  @interval 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_check()
    {:ok, state}
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

  def check_resources do
    try do
      case System.cmd("docker", ["stats", "--no-stream"]) do
        {output, 0} ->
          parse_and_check_stats(output)
        {_, status} ->
          Logger.error("Failed to get docker stats, exit code: #{status}")
      end
    rescue
      e in ErlangError ->
        Logger.error("Failed to execute docker command (is it installed?): #{inspect(e)}")
    end
  end

  defp parse_and_check_stats(output) do
    # Skip the header line
    lines = output |> String.split("\n", trim: true) |> Enum.drop(1)

    Enum.each(lines, fn line ->
      # Docker stats output columns:
      # CONTAINER ID | NAME | CPU % | MEM USAGE / LIMIT | MEM % | NET I/O | BLOCK I/O | PIDS
      parts = String.split(line, ~r/\s{2,}/)

      if length(parts) >= 5 do
        container_id = Enum.at(parts, 0)
        name = Enum.at(parts, 1)
        cpu_str = Enum.at(parts, 2)
        mem_str = Enum.at(parts, 4)

        check_limit("CPU", container_id, name, cpu_str)
        check_limit("Memory", container_id, name, mem_str)
      else
        Logger.warn("Failed to parse docker stats line: #{line}")
      end
    end)
  end

  defp check_limit(resource_name, id, name, value_str) do
    # Remove the '%' sign and convert to float
    clean_str = String.replace(value_str, "%", "") |> String.trim()

    case Float.parse(clean_str) do
      {value, _} ->
        if value > 80.0 do
          Logger.warn("Resource Watchdog: Container #{name} (#{id}) #{resource_name} usage is high: #{value}%")
        end
      :error ->
        # If float parsing fails, try integer parsing
        case Integer.parse(clean_str) do
          {value, _} ->
            if value > 80 do
              Logger.warn("Resource Watchdog: Container #{name} (#{id}) #{resource_name} usage is high: #{value}%")
            end
          :error ->
            Logger.warn("Failed to parse #{resource_name} value for container #{id}: #{value_str}")
        end
    end
  end
end
