defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  A GenServer that runs continuously (every 5 minutes) to monitor Docker
  container CPU and RAM usage, logging warnings if they exceed 80%.
  """
  use GenServer
  require Logger

  # 5 minutes in milliseconds
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
    Logger.info("Running Resource Watchdog Check...")

    try do
      case System.cmd("docker", ["stats", "--no-stream"]) do
        {output, 0} ->
          parse_and_check_stats(output)

        {err, code} ->
          Logger.error("Failed to fetch docker stats (code #{code}): #{err}")
      end
    rescue
      e in ErlangError ->
        Logger.warning("Docker CLI not available, skipping Resource Watchdog check: #{inspect(e)}")
    end
  end

  defp parse_and_check_stats(output) do
    # Skip the header line
    lines = output |> String.split("\n", trim: true) |> Enum.drop(1)

    Enum.each(lines, fn line ->
      # Docker stats default output columns separated by 2+ spaces
      parts = String.split(line, ~r/\s{2,}/)

      if length(parts) >= 5 do
        # Format is roughly: CONTAINER ID | NAME | CPU % | MEM USAGE / LIMIT | MEM % | NET I/O | BLOCK I/O | PIDS
        container_name = Enum.at(parts, 1)
        cpu_str = Enum.at(parts, 2)
        mem_str = Enum.at(parts, 4)

        check_resource(container_name, "CPU", cpu_str)
        check_resource(container_name, "Memory", mem_str)
      end
    end)
  end

  defp check_resource(container_name, resource_name, value_str) do
    # Clean up the string (e.g., "0.05%" -> 0.05)
    clean_val = String.replace(value_str, "%", "")

    case Float.parse(clean_val) do
      {value, _} ->
        if value > 80.0 do
          Logger.warning("RESOURCE ALERT: Container #{container_name} #{resource_name} usage is high (#{value}%). Potential OOM/Starvation risk.")
        end
      :error ->
        Logger.debug("Could not parse #{resource_name} value: #{value_str}")
    end
  end
end
