defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Monitors Docker resource usages continuously and logs warnings
  if CPU or RAM usages exceed 80%.
  """
  use GenServer
  require Logger

  # 5 minutes in milliseconds
  @interval 5 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_monitoring()
    {:ok, state}
  end

  def handle_info(:monitor, state) do
    perform_monitoring()
    schedule_monitoring()
    {:noreply, state}
  end

  defp schedule_monitoring do
    Process.send_after(self(), :monitor, @interval)
  end

  def perform_monitoring do
    Logger.info("Starting Resource Monitoring...")

    try do
      case System.cmd("docker", ["stats", "--no-stream"]) do
        {output, 0} ->
          parse_and_check_stats(output)

        {err, code} ->
          Logger.warning("Docker stats command failed with code #{code}: #{err}")
      end
    rescue
      e in ErlangError ->
        Logger.error("Failed to execute docker command (executable may be missing): #{inspect(e)}")
    end
  end

  defp parse_and_check_stats(output) do
    # Output has a header, followed by lines for each container.
    # We skip the first line (header) or we can just parse lines starting with container IDs.
    lines = String.split(output, "\n", trim: true)

    Enum.each(Enum.drop(lines, 1), fn line ->
      # Split by 2 or more spaces
      parts = String.split(line, ~r/\s{2,}/)

      if length(parts) >= 5 do
        # parts[0] is CONTAINER ID
        # parts[1] is NAME
        # parts[2] is CPU %
        # parts[3] is MEM USAGE / LIMIT
        # parts[4] is MEM %

        container_id = Enum.at(parts, 0)
        cpu_str = Enum.at(parts, 2)
        mem_str = Enum.at(parts, 4)

        check_usage(container_id, "CPU", cpu_str)
        check_usage(container_id, "Memory", mem_str)
      end
    end)
  end

  defp check_usage(container_id, metric_name, usage_str) do
    # usage_str looks like "0.00%" or "85.5%"
    clean_str = String.replace(usage_str, "%", "") |> String.trim()

    case Float.parse(clean_str) do
      {usage, _} ->
        if usage > 80.0 do
          Logger.warning("ResourceWatchdog: Container #{container_id} is exceeding #{metric_name} quota (#{usage}%)")
        end
      :error ->
        Logger.debug("ResourceWatchdog: Failed to parse #{metric_name} usage for #{container_id}: #{usage_str}")
    end
  end
end
